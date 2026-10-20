import QtQuick
import qs.common
import qs.services
import qs.widgets

// The month around today; today is a lavender circle. Scroll or ‹ › to change
// month, click the month name to come back.
Item {
    id: cal

    readonly property date today: Time.date
    property int year: today.getFullYear()
    property int month: today.getMonth() // 0–11
    property int dir: 0                  // which way the last month change went, for the slide

    // Qt counts Monday=1…Sunday=7, JavaScript Sunday=0…Saturday=6
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property var cells: cal.monthCells(year, month, firstDay, today)
    readonly property var weekdays: cal.weekdayNames(firstDay)
    readonly property int cell: Theme.rem(2.15 * Theme.ui.k)

    implicitWidth: cell * 7
    implicitHeight: col.implicitHeight

    function reset() {
        cal.dir = 0;
        cal.year = cal.today.getFullYear();
        cal.month = cal.today.getMonth();
    }

    function shift(d) {
        const m = cal.month + d;
        cal.dir = d;
        cal.year += Math.floor(m / 12);
        cal.month = ((m % 12) + 12) % 12;
        slide.restart();
    }

    // 6 weeks × 7 days, starting on the locale's first weekday
    function monthCells(y, m, first, now) {
        const lead = (new Date(y, m, 1).getDay() - first + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === m,
                today: d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate(),
                weekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return out;
    }

    function weekdayNames(first) {
        const out = [];
        for (let i = 0; i < 7; i++)
            out.push(Qt.locale().dayName((first + i) % 7, Locale.ShortFormat).slice(0, 2));
        return out;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        property real wheelAcc: 0
        onWheel: event => {
            wheelAcc += event.angleDelta.y;
            if (wheelAcc >= 120 || wheelAcc <= -120) {
                cal.shift(wheelAcc > 0 ? -1 : 1);
                wheelAcc = 0;
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.space.sm

        Item {
            width: parent.width
            height: Theme.rem(1.95 * Theme.ui.k)

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(new Date(cal.year, cal.month, 1), "MMMM yyyy")
                font.pixelSize: Theme.ui.title
                font.weight: Font.DemiBold
                color: monthHit.containsMouse ? Theme.colors.accent : Theme.colors.text

                MouseArea {
                    id: monthHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cal.reset()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.rem(0.15)

                Repeater {
                    model: [-1, 1]

                    delegate: Rectangle {
                        id: nav
                        required property int modelData
                        width: Theme.rem(1.85 * Theme.ui.k)
                        height: width
                        radius: Theme.radius.sm
                        color: navHit.containsMouse ? Theme.colors.raised : "transparent"

                        StyledText {
                            anchors.centerIn: parent
                            text: nav.modelData < 0 ? "󰅁" : "󰅂"
                            color: navHit.containsMouse ? Theme.colors.text : Theme.colors.subtext
                            font.pixelSize: Theme.ui.icon
                        }

                        MouseArea {
                            id: navHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cal.shift(nav.modelData)
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: weekRow.height + grid.height
            clip: true

            Row {
                id: weekRow
                Repeater {
                    model: cal.weekdays
                    delegate: StyledText {
                        required property string modelData
                        width: cal.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.colors.faint
                        font.pixelSize: Theme.ui.tiny
                    }
                }
            }

            Grid {
                id: grid
                y: weekRow.height + Theme.space.xs
                columns: 7

                Repeater {
                    model: cal.cells

                    delegate: Item {
                        id: day
                        required property var modelData
                        width: cal.cell
                        height: cal.cell

                        Rectangle {
                            anchors.centerIn: parent
                            width: cal.cell - Theme.rem(0.3)
                            height: width
                            radius: width / 2
                            color: day.modelData.today ? Theme.colors.accent : dayHit.containsMouse ? Theme.colors.raised : "transparent"
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: day.modelData.day
                            font.pixelSize: Theme.ui.small
                            font.weight: day.modelData.today ? Font.Bold : Font.Normal
                            color: {
                                if (day.modelData.today)
                                    return Theme.colors.ink;
                                if (!day.modelData.inMonth)
                                    return Theme.colors.faint;
                                return day.modelData.weekend ? Theme.colors.subtext : Theme.colors.text;
                            }
                        }

                        MouseArea {
                            id: dayHit
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }

                // a month change slides the days in from the side it came from
                ParallelAnimation {
                    id: slide
                    NumberAnimation { target: grid; property: "x"; from: cal.dir * Theme.rem(1.2); to: 0; duration: Theme.anim.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.anim.enter }
                    NumberAnimation { target: grid; property: "opacity"; from: 0.25; to: 1; duration: Theme.anim.normal }
                }
            }
        }
    }
}
