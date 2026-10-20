import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common
import qs.services
import qs.widgets

// Workspaces as numbers. The active one sits on a lavender square that slides
// over when you switch; workspaces with windows are bright, empty ones faint.
// Click to go there, scroll anywhere on the bar to step through them.
Item {
    id: ws

    required property HyprlandMonitor monitor

    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property var all: Hyprland.workspaces.values
    readonly property var ids: Hypr.workspaceIds(all, monitor?.name ?? "", Config.bar.workspaces)
    readonly property int activeIndex: ids.indexOf(activeId)
    readonly property int cell: Theme.rem(1.75 * Theme.ui.k)
    readonly property int gap: Theme.rem(0.22)

    property real wheelAcc: 0

    function byId(id) {
        for (let i = 0; i < all.length; i++)
            if (all[i].id === id)
                return all[i];
        return null;
    }

    function wheel(event) {
        ws.wheelAcc += event.angleDelta.y || -event.angleDelta.x;
        let d = 0;
        while (ws.wheelAcc >= 120) {
            d--;
            ws.wheelAcc -= 120;
        }
        while (ws.wheelAcc <= -120) {
            d++;
            ws.wheelAcc += 120;
        }
        if (d)
            Hypr.focusWorkspace(Hypr.stepWorkspace(ws.ids, ws.activeId, d));
    }

    implicitWidth: row.implicitWidth
    implicitHeight: cell

    // the square under the active number
    Rectangle {
        visible: ws.activeIndex >= 0
        x: Math.max(0, ws.activeIndex) * (ws.cell + ws.gap)
        width: ws.cell
        height: ws.cell
        radius: Theme.radius.sm
        color: Theme.colors.accent

        Behavior on x {
            NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.move }
        }
    }

    Row {
        id: row
        spacing: ws.gap

        Repeater {
            model: ws.ids

            delegate: Item {
                id: slot

                required property int modelData
                readonly property var w: ws.byId(modelData)
                readonly property bool active: modelData === ws.activeId
                readonly property bool occupied: (w?.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: (w?.urgent ?? false) && !active

                width: ws.cell
                height: ws.cell

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius.sm
                    color: Theme.colors.raised
                    visible: hit.containsMouse && !slot.active
                }

                StyledText {
                    anchors.centerIn: parent
                    text: slot.modelData
                    font.pixelSize: Theme.ui.small
                    font.weight: slot.active ? Font.Bold : Font.Medium
                    color: {
                        if (slot.active)
                            return Theme.colors.ink;
                        if (slot.urgent)
                            return Theme.colors.warn;
                        return slot.occupied ? Theme.colors.text : Theme.colors.faint;
                    }

                    Behavior on color {
                        ColorAnimation { duration: Theme.anim.fast }
                    }
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hypr.focusWorkspace(slot.modelData)
                    onWheel: event => ws.wheel(event)
                }
            }
        }
    }
}
