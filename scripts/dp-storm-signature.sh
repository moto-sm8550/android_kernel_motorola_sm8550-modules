#!/bin/sh
#
# dp-storm-signature.sh - one-line DP/SDE health signature for a dmesg dump.
#
# Usage:
#   adb shell dmesg > after.log
#   ./scripts/dp-storm-signature.sh after.log
#   dmesg | ./scripts/dp-storm-signature.sh
#
# The output is a single line of stable name=value fields, so two runs can be
# compared with "diff before.sig after.sig" or pasted side by side.
#
#   dp_teardown      dp_bridge_disable calls (stream teardowns)
#   dp_enable        dp_bridge_pre_enable calls (link/mode enables)
#   stream_only      teardowns that kept the host and link alive
#   host_pwrdn       idle external-display host power-downs
#   retrain          dp_ctrl_link_maintenance retrains
#   host_not_ready   enables refused because the host was not ready
#   commit_fail      wait-for-commit-done failures
#   intf_stopped     commit-done waits abandoned because the interface timing
#                    engine was already off (sink lost mid-commit), i.e. the
#                    teardown the wait used to report as a failure. Logged at
#                    info level, so a plain dmesg capture carries it.
#   vsync_timeout    encoder vsync-event wait timeouts (84 ms stalls)
#   vblank_einval    phys vblank disable with no registered irq (-EINVAL)
#   sink_gate        atomic commits refused because the sink was gone
#   refresh_reject   modes dropped by max_refresh_rate
#   hpd_high/low     connect / disconnect processing runs
#   hdcp_probe       source HDCP capability probes (want ~1 per connect)
#   hdcp_app_fail    failed TZ "ops" app loads
#   bw06/bw10/bw20/bw30   rates seen in dp_ctrl_link_setup
#   max_teardown_ms  longest dp_display_pre_disable -> dp_bridge_post_disable
#   dsi_switch       internal panel DSI mode switches (refresh-rate changes)
#   dsi_60/dsi_90    those switches by rate; they only add up to dsi_switch
#                    when the panel offers no other rate

if [ "$#" -gt 0 ] && [ ! -r "$1" ]; then
	echo "cannot read $1" >&2
	exit 1
fi

awk '
function note(k) { c[k]++ }

BEGIN { max_gap = 0; have_pre = 0 }

{
	# kernel stamps look like "[ 327557.430801]"; skip continuation lines
	if (!match($0, /^\[ *[0-9]+\.[0-9]+\]/))
		next
	ts = substr($0, RSTART + 1, RLENGTH - 2) + 0

	if (index($0, "dp_bridge_disable"))               note("dp_teardown")
	if ($0 ~ /dp_bridge_pre_enable.*##/)              note("dp_enable")
	if (index($0, "stream only teardown"))            note("stream_only")
	if (index($0, "powering down host"))              note("host_pwrdn")
	if (index($0, "dp_ctrl_link_maintenance"))        note("retrain")
	if (index($0, "host not ready"))                  note("host_not_ready")
	if (index($0, "wait for commit done fail"))       note("commit_fail")
	if (index($0, "dropping commit done wait"))       note("intf_stopped")
	if (index($0, "vsync event complete timed out"))  note("vsync_timeout")
	if (index($0, "control vblank irq error"))        note("vblank_einval")
	if (index($0, "no longer ready, failing commit")) note("sink_gate")
	if (index($0, "max_refresh_rate"))                note("refresh_reject")
	if (index($0, "add DP_STATE_CONNECTED"))          note("hpd_high")
	if (index($0, "remove DP_STATE_CONNECTED"))       note("hpd_low")
	if ($0 ~ /check_source_hdcp_caps.*##/)            note("hdcp_probe")
	if (index($0, "ops app load failed"))             note("hdcp_app_fail")

	if (index($0, "dp_ctrl_link_setup") &&
			match($0, /bw_code=[0-9]+/))
		note("bw" substr($0, RSTART + 8, RLENGTH - 8))

	if (index($0, "dp_display_pre_disable")) {
		pre_ts = ts
		have_pre = 1
	} else if (index($0, "dp_bridge_post_disable") && have_pre) {
		gap = int((ts - pre_ts) * 1000 + 0.5)
		if (gap > max_gap)
			max_gap = gap
		have_pre = 0
	}

	if (index($0, "dsi_display_set_mode")) {
		note("dsi_switch")
		if (index($0, "fps=60"))
			note("dsi_60")
		if (index($0, "fps=90"))
			note("dsi_90")
	}
}
END {
	printf "dp_teardown=%d dp_enable=%d stream_only=%d host_pwrdn=%d " \
		"retrain=%d host_not_ready=%d commit_fail=%d intf_stopped=%d " \
		"vsync_timeout=%d " \
		"vblank_einval=%d sink_gate=%d refresh_reject=%d hpd_high=%d " \
		"hpd_low=%d hdcp_probe=%d hdcp_app_fail=%d bw06=%d bw10=%d " \
		"bw20=%d bw30=%d max_teardown_ms=%d dsi_switch=%d dsi_60=%d " \
		"dsi_90=%d\n", \
		c["dp_teardown"], c["dp_enable"], c["stream_only"], \
		c["host_pwrdn"], c["retrain"], c["host_not_ready"], \
		c["commit_fail"], c["intf_stopped"], c["vsync_timeout"], \
		c["vblank_einval"], \
		c["sink_gate"], c["refresh_reject"], c["hpd_high"], \
		c["hpd_low"], c["hdcp_probe"], c["hdcp_app_fail"], \
		c["bw6"], c["bw10"], c["bw20"], c["bw30"], max_gap, \
		c["dsi_switch"], c["dsi_60"], c["dsi_90"]
}
' "${1:-/dev/stdin}"
