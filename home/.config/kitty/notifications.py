# Puts an expiry on every notification, whoever sent it.
#
# kitty calls main() for each notification before dispatching it
# (NotificationManager.notify_with_command -> is_notification_filtered), and the
# NotificationCommand handed over is still mutable. So this is the one place
# that can bound notifications this setup does not send itself: OSC 99 from any
# program in any pane, and kitty's own notify_on_cmd_finish.
#
# timeout is in milliseconds: -2 unset, -1 the OS policy, 0 never, and anything
# above zero is enforced by kitty closing the notification itself - which is
# what clears it out of Notification Center rather than just off the screen.
#
# Returning True would filter a notification out. This never does; it only ever
# shortens how long one lives.
#
# Loaded once, in NotificationManager.__init__, so a change here needs kitty
# restarted. Reloading the config does not pick it up.
MAX_MS = 10000


def main(notification) -> bool:
    try:
        timeout = notification.timeout
        # <= 0 covers "never" (0) and the OS policy (-1, or -2 unset), none of
        # which kitty will close on its own.
        if timeout <= 0 or timeout > MAX_MS:
            notification.timeout = MAX_MS
    except Exception:
        pass  # never let this stop a notification being delivered
    return False
