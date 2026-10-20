pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.common

// The notification daemon. Owns org.freedesktop.Notifications (replaces mako).
//
// Every notification becomes an Entry. Entries with `popup: true` are on screen;
// the rest is history, which the notification centre shows. An Entry
// keeps a frozen copy of its text after the app closes the notification, because
// Quickshell destroys the Notification object at that point.
//
// From a terminal or a keybind:
//   qs ipc call notifs toggleDnd      do-not-disturb (critical still shows)
//   qs ipc call notifs hidePopups     slide everything into history
//   qs ipc call notifs dismissAll     clear everything
Singleton {
    id: root

    property var entries: []                                // newest first
    readonly property var popups: entries.filter(e => e.popup)
    readonly property int count: entries.length
    property bool dnd: false

    // Unread = arrived since you last looked at the notification centre.
    property int seenUid: 0
    readonly property var unread: entries.filter(e => e.uid > seenUid)
    readonly property bool centreOpen: Drawers.current === "centre"
    onCentreOpenChanged: {
        if (centreOpen) {
            markSeen();
            hideAllPopups(); // they're all in the list now
        }
    }

    function markSeen() {
        seenUid = nextUid - 1;
    }

    readonly property date now: clock.date
    property int nextUid: 1

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    NotificationServer {
        id: server
        keepOnReload: true            // survive config reloads (they come back as history)
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true    // we keep them for the notification centre

        onNotification: n => root.receive(n)
    }

    // ── incoming ─────────────────────────────────────────────────────────────

    function receive(n) {
        n.tracked = true;
        // no popups while the notification centre is open: they land in the list you're looking at
        const show = !n.lastGeneration && !centreOpen && (!dnd || n.urgency === NotificationUrgency.Critical);

        // The app replaced a notification we already have: refresh it in place.
        for (const e of entries) {
            if (e.notification === n) {
                e.refresh(show);
                entries = [e].concat(entries.filter(x => x !== e));
                return;
            }
        }

        const e = entryComp.createObject(root, { notification: n, popup: show, uid: nextUid++ });
        if (centreOpen)
            markSeen();
        e.closed.connect(reason => root.handleClosed(e, reason));

        const next = [e].concat(entries);
        let shown = 0;
        for (const x of next)
            if (x.popup && ++shown > Config.notifications.maxPopups)
                x.popup = false;
        while (next.length > Config.notifications.maxHistory) {
            const old = next.pop();
            drop(old);
            old.gone = true;
            old.destroy(2000);
        }
        entries = next;
    }

    // The app (or another client) closed it.
    function handleClosed(e, reason) {
        if (reason === NotificationCloseReason.CloseRequested || e.isTransient)
            remove(e); // withdrawn by the app: stale, don't keep it
        else
            e.popup = false;
    }

    // ── what the UI calls ────────────────────────────────────────────────────

    // Left click: gone for good.
    function dismiss(e) {
        if (!e.gone)
            remove(e);
    }

    // Timed out / pushed out: off screen, kept in history.
    function hidePopup(e) {
        if (e.gone)
            return;
        if (e.isTransient)
            remove(e);
        else
            e.popup = false;
    }

    // Right click: run the app's "default" action if it has one (e.g. jump to the
    // Discord channel) and raise its window — on Wayland apps usually can't raise
    // themselves. No default action: focus the app's window, or launch it.
    function open(e) {
        if (e.gone)
            return;
        const n = e.notification;
        if (n) {
            for (let i = 0; i < n.actions.length; i++) {
                if (n.actions[i].identifier === "default") {
                    invokeAction(e, n.actions[i], true);
                    focusApp(e, false);
                    return;
                }
            }
        }
        focusApp(e, true);
        remove(e);
    }

    // Action buttons. `close` forces the card away even for resident notifications.
    function invokeAction(e, action, close) {
        const n = e.notification;
        if (e.gone || !n)
            return;
        if (n.resident && !close) {
            action.invoke(); // e.g. media "next": keep the card
            return;
        }
        const resident = n.resident;
        e.detach();
        action.invoke();    // non-resident: Quickshell dismisses it for us
        if (resident)
            n.dismiss();
        forget(e);
    }

    function focusApp(e, allowLaunch) {
        const keys = [e.desktopEntry, e.appName].filter(k => !!k).map(k => k.toLowerCase());
        if (keys.length === 0)
            return false;

        const windows = ToplevelManager.toplevels.values;
        for (let i = 0; i < windows.length; i++) {
            const id = (windows[i].appId || "").toLowerCase();
            if (id && keys.some(k => id === k || id.includes(k) || (id.length > 3 && k.includes(id)))) {
                windows[i].activate();
                return true;
            }
        }

        // Not running: launch it, but only via an exact desktop entry (no guessing).
        const app = allowLaunch && e.desktopEntry ? DesktopEntries.byId(e.desktopEntry) : null;
        if (app) {
            app.execute();
            return true;
        }
        return false;
    }

    function hideAllPopups() {
        for (const e of entries.slice())
            if (e.popup)
                hidePopup(e);
    }

    function dismissAll() {
        const all = entries;
        entries = [];
        for (const e of all) {
            drop(e);
            e.gone = true;
            e.destroy(2000);
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function remove(e) {
        if (e.gone)
            return;
        drop(e);
        forget(e);
    }

    function forget(e) {
        if (e.gone)
            return;
        e.gone = true;
        entries = entries.filter(x => x !== e);
        e.destroy(2000); // let the exit animation finish first
    }

    // Stop tracking on the D-Bus side (no-op if the app already closed it).
    function drop(e) {
        const n = e.notification;
        e.detach();
        if (n)
            n.dismiss();
    }

    function timeoutFor(e) {
        const c = Config.notifications;
        if (e.urgency === NotificationUrgency.Critical && c.criticalSticky)
            return 0;
        if (c.respectAppTimeout && e.expireTimeout > 0) {
            // spec says ms, Quickshell reports seconds; accept either
            const ms = e.expireTimeout > 600 ? e.expireTimeout : e.expireTimeout * 1000;
            return Math.max(1500, Math.min(120000, ms));
        }
        return e.urgency === NotificationUrgency.Low ? c.timeoutLow : c.timeout;
    }

    function relTime(t) {
        const s = Math.max(0, (now.getTime() - t.getTime()) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return `${Math.floor(s / 60)}m`;
        if (s < 86400)
            return `${Math.floor(s / 3600)}h`;
        return Qt.formatDate(t, "d MMM");
    }

    // ── one notification ─────────────────────────────────────────────────────

    component Entry: QtObject {
        id: entry

        property Notification notification
        property int uid
        property bool popup: true
        property bool gone: false // removed; only kept alive for the exit animation
        property date time: new Date()
        property int revision: 0 // bumps when the app updates it (restarts the timer)

        // Live while the notification exists; freeze() turns them into plain copies.
        property string appName: notification?.appName ?? ""
        property string appIcon: notification?.appIcon ?? ""
        property string desktopEntry: notification?.desktopEntry ?? ""
        property string summary: notification?.summary ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property int urgency: notification?.urgency ?? NotificationUrgency.Normal
        property real expireTimeout: notification?.expireTimeout ?? -1
        // ("transient" is a reserved word in QML, hence isTransient + the bracket lookup)
        property bool isTransient: notification ? notification["transient"] : false

        readonly property bool alive: notification !== null
        readonly property color accent: urgency === NotificationUrgency.Critical
            ? Theme.colors.critical
            : AppColors.forApp(appName, desktopEntry, appIcon)

        signal closed(int reason)

        function freeze() {
            const n = notification;
            if (!n)
                return;
            appName = n.appName;
            appIcon = n.appIcon;
            desktopEntry = n.desktopEntry;
            summary = n.summary;
            body = n.body;
            image = n.image;
            urgency = n.urgency;
            expireTimeout = n.expireTimeout;
            isTransient = n["transient"];
        }

        // Keep the text, let go of the live object.
        function detach() {
            freeze();
            notification = null;
        }

        function refresh(show) {
            time = new Date();
            revision++;
            if (show)
                popup = true;
        }

        readonly property Connections watcher: Connections {
            target: entry.notification
            function onClosed(reason) {
                entry.detach();
                entry.closed(reason);
            }
        }
    }

    Component {
        id: entryComp
        Entry {}
    }

    IpcHandler {
        target: "notifs"

        function toggleDnd(): bool {
            root.dnd = !root.dnd;
            return root.dnd;
        }
        function setDnd(value: bool): void {
            root.dnd = value;
        }
        function hidePopups(): void {
            root.hideAllPopups();
        }
        function dismissAll(): void {
            root.dismissAll();
        }
        function count(): int {
            return root.entries.length;
        }
    }
}
