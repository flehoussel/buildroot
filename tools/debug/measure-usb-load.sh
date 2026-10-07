#!/bin/sh
# Standalone diagnostic script for the orangepi-z2w: measures the CPU cost of
# the MUSB OTG controller, which runs in PIO mode (musb_sunxi has no DMA
# controller, so the CPU copies every byte between memory and the FIFO).
# Not part of the image - scp this to the board and run it directly (needs
# OpenSSH with sftp and root password login, see README.md).
#
# Samples once per second, while an Android Auto session is running:
#   - system-wide CPU usage (usr / sys / irq / softirq / idle)
#   - the busiest core, to spot a single saturated core on the 4-core SoC
#   - the musb-hdrc interrupt rate (IRQ/s)
#   - the CPU used by aa-proxy-rs, in % of one core
#   - the WiFi throughput (wlan0 RX/TX, Mbit/s), as a proxy for the data
#     relayed to the USB side since aa-proxy-rs runs in passthrough
#   - the CPU frequency (cpu0), to read the CPU percentages in context
#   - the SoC temperature (hottest thermal zone)
#
# The WiFi interface can be changed with WLAN_IF=<name>.
#
# Usage:
#   ./measure-usb-load.sh start     # begin sampling in the background
#   ... run aa-proxy-rs + DHU / car for a while ...
#   ./measure-usb-load.sh stop      # stop sampling, print a summary
#
# Output (in /tmp):
#   usb-load.raw  - raw /proc snapshots, parsed at stop time so that sampling
#                   itself stays cheap
#   usb-load.csv  - one line per second, ready for a spreadsheet
#
# Needs busybox sh + awk only. Assumes USER_HZ=100.

PID_FILE=/tmp/measure-usb-load.pid
RAW=/tmp/usb-load.raw
CSV=/tmp/usb-load.csv
PROC_NAME=${PROC_NAME:-aa-proxy-rs}
WLAN_IF=${WLAN_IF:-wlan0}

start() {
	if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
		echo "Already running (pid $(cat "$PID_FILE"))"
		exit 1
	fi
	: > "$RAW"
	(
		while true; do
			echo "S $(cut -d' ' -f1 /proc/uptime)"
			grep '^cpu' /proc/stat
			grep -i musb /proc/interrupts | sed 's/^/I /'
			# aa-proxy-rs may restart during a session: look the pid up each time
			pid=$(pidof "$PROC_NAME" 2>/dev/null | cut -d' ' -f1)
			if [ -n "$pid" ] && [ -r "/proc/$pid/stat" ]; then
				# fields 14/15 (utime/stime); strip "pid (comm)" first, comm may hold spaces
				sed 's/^[0-9]* ([^)]*) //' "/proc/$pid/stat" | awk '{print "P " $12, $13}'
			fi
			sleep 1
		done
	) >> "$RAW" &
	echo $! > "$PID_FILE"
	echo "Sampling started (pid $!), writing to $RAW"
}

summarize() {
	awk -v csv="$CSV" -v wlan="$WLAN_IF" '
	function sumirq(line,   n, i, s, f) {
		# "I  57:  123  0  0  0  GICv3  ..." -> add up the per-CPU counters
		n = split(line, f, " ")
		s = 0
		for (i = 3; i <= n; i++) {
			if (f[i] !~ /^[0-9]+$/) break
			s += f[i]
		}
		return s
	}
	function flush(   dt, dtot, c, tot, busiest, bi, pct) {
		if (have_prev && t > pt && ntot[0] > 0) {
			dt = t - pt
			dtot = ntot[0] - ptot[0]
			if (dtot > 0) {
				usr = (cu[0] - pcu[0]) * 100 / dtot
				sys = (cs[0] - pcs[0]) * 100 / dtot
				irq = ((ci[0] - pci[0]) + (cq[0] - pcq[0])) * 100 / dtot
				idl = (cid[0] - pcid[0]) * 100 / dtot
				busiest = 0
				for (c = 1; c < ncpu; c++) {
					tot = ntot[c] - ptot[c]
					if (tot > 0) {
						pct = 100 - (cid[c] - pcid[c]) * 100 / tot
						if (pct > busiest) busiest = pct
					}
				}
				irqs = (musb - pmusb) / dt
				# aa-proxy-rs may have restarted: its counters start again from 0
				aa = (proc >= pproc) ? (proc - pproc) / dt : -1
				rx = (have_net && have_pnet && rxb >= prxb) ? (rxb - prxb) * 8 / dt / 1000000 : -1
				tx = (have_net && have_pnet && txb >= ptxb) ? (txb - ptxb) * 8 / dt / 1000000 : -1
				n++
				printf "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f,%.1f,%.2f,%.2f,%.0f,%.1f\n", t, 100 - idl, usr, sys, irq, busiest, irqs, aa, rx, tx, fmhz, tmax >> csv
				s_cpu += 100 - idl; s_sys += sys; s_irq += irq; s_irqs += irqs
				if (100 - idl > m_cpu) m_cpu = 100 - idl
				if (busiest > m_core) m_core = busiest
				if (irqs > m_irqs) m_irqs = irqs
				if (aa >= 0) { n_aa++; s_aa += aa; if (aa > m_aa) m_aa = aa }
				if (rx >= 0) { n_net++; s_rx += rx; s_tx += tx; if (rx > m_rx) m_rx = rx; if (tx > m_tx) m_tx = tx }
				if (fmhz > 0) { n_f++; s_f += fmhz; if (fmhz > m_f) m_f = fmhz; if (!min_f || fmhz < min_f) min_f = fmhz }
				if (tmax > 0) { n_t++; s_t += tmax; if (tmax > m_t) m_t = tmax }
			}
		}
		if (t > 0) {
			for (c = 0; c < ncpu; c++) {
				pcu[c] = cu[c]; pcs[c] = cs[c]; pci[c] = ci[c]; pcq[c] = cq[c]
				pcid[c] = cid[c]; ptot[c] = ntot[c]
			}
			pmusb = musb; pproc = proc; pt = t; have_prev = 1
			prxb = rxb; ptxb = txb; have_pnet = have_net
		}
	}
	BEGIN {
		print "uptime,cpu_pct,usr_pct,sys_pct,irq_softirq_pct,busiest_core_pct,musb_irq_per_s,aa_proxy_pct_of_1_core,wifi_rx_mbit_s,wifi_tx_mbit_s,cpu_mhz,temp_c" > csv
	}
	$1 == "S" { if (t > 0) flush(); t = $2; if (!first_t) first_t = t; musb = 0; ncpu = 0; have_musb = 0; have_net = 0; fmhz = 0; tmax = 0; next }
	/^cpu/ {
		id = ($1 == "cpu") ? 0 : substr($1, 4) + 1
		cu[id] = $2 + $3; cs[id] = $4; cid[id] = $5 + $6
		ci[id] = $7; cq[id] = $8
		ntot[id] = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9
		if (id + 1 > ncpu) ncpu = id + 1
		next
	}
	$1 == "I" { musb += sumirq($0); next }
	$1 == "P" { proc = $2 + $3; next }
	$1 == "N" { rxb = $2; txb = $3; have_net = 1; next }
	$1 == "F" { fmhz = $2 / 1000; next }
	$1 == "T" { if ($2 / 1000 > tmax) tmax = $2 / 1000; next }
	END {
		if (t > 0) flush()
		if (n == 0) { print "No usable samples (was it running long enough?)"; exit }
		printf "\n%d samples over %.0f s, %d CPU(s)\n\n", n, t - first_t, ncpu - 1
		printf "%-34s %8s %8s\n", "", "avg", "max"
		printf "%-34s %7.1f%% %7.1f%%\n", "CPU, whole system", s_cpu / n, m_cpu
		printf "%-34s %7.1f%%\n", "  of which sys", s_sys / n
		printf "%-34s %7.1f%%\n", "  of which irq+softirq", s_irq / n
		printf "%-34s %8s %7.1f%%\n", "busiest core", "", m_core
		printf "%-34s %8.0f %8.0f\n", "musb-hdrc IRQ/s", s_irqs / n, m_irqs
		printf "%-34s %7.1f%% %7.1f%%\n", "aa-proxy-rs (100% = 1 core)", n_aa ? s_aa / n_aa : 0, m_aa
		if (n_net) {
			printf "%-34s %8.2f %8.2f\n", "WiFi RX (Mbit/s)", s_rx / n_net, m_rx
			printf "%-34s %8.2f %8.2f\n", "WiFi TX (Mbit/s)", s_tx / n_net, m_tx
		} else
			printf "WiFi throughput: no %s counters found\n", wlan
		if (n_f)
			printf "%-34s %8.0f %8.0f   (min %.0f)\n", "CPU frequency (MHz)", s_f / n_f, m_f, min_f
		else
			print "CPU frequency: no cpufreq on this board"
		if (n_t)
			printf "%-34s %8.1f %8.1f\n", "Temperature (C, hottest zone)", s_t / n_t, m_t
		else
			print "Temperature: no thermal zone readable"
	}
	' "$RAW"
}

stop() {
	if [ ! -f "$PID_FILE" ]; then
		echo "Not running (no $PID_FILE)"
		exit 1
	fi
	kill "$(cat "$PID_FILE")" 2>/dev/null
	rm -f "$PID_FILE"
	summarize
	echo
	echo "Per-second data: $CSV"
}

case "$1" in
	start) start ;;
	stop) stop ;;
	*)
		echo "Usage: $0 {start|stop}"
		exit 1
		;;
esac
