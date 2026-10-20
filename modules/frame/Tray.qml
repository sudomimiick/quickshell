import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.common

// App tray icons (Discord, Steam, …), in grey until you hover one. Hidden when there are none.
//   click → the app · right click → its menu · middle click → its secondary action
Item {
    id: tray

    required property var menuWindow   // the bar window, to anchor menus to

    // (counted from the items themselves: a hidden parent would hide the children too)
    readonly property int shown: {
        const all = SystemTray.items.values;
        let n = 0;
        for (let i = 0; i < all.length; i++)
            if (all[i].status !== Status.Passive)
                n++;
        return n;
    }

    visible: Config.bar.tray && shown > 0
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.rem(Config.bar.height) - Theme.rem(0.7)

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.rem(0.15)

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: slot

                required property SystemTrayItem modelData

                // "Passive" items have nothing to say right now
                visible: modelData.status !== Status.Passive
                width: Theme.ui.cell
                height: tray.height

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Theme.ui.icon
                    source: slot.modelData.icon
                    asynchronous: true
                    opacity: hit.containsMouse ? 1 : 0.75
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        saturation: hit.containsMouse ? 0 : -1
                    }
                }

                MouseArea {
                    id: hit

                    property real wheelAcc: 0

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: event => {
                        const item = slot.modelData;
                        if (event.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                        } else if (event.button === Qt.RightButton || item.onlyMenu) {
                            if (item.hasMenu) {
                                const p = slot.mapToItem(null, 0, slot.height);
                                item.display(tray.menuWindow, p.x, p.y);
                            }
                        } else {
                            item.activate();
                        }
                    }
                    onWheel: event => {
                        wheelAcc += event.angleDelta.y;
                        if (Math.abs(wheelAcc) >= 120) {
                            slot.modelData.scroll(Math.round(wheelAcc / 120), false);
                            wheelAcc = 0;
                        }
                    }
                }
            }
        }
    }
}
