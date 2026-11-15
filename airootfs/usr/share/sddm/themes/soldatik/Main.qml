import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#0a0a0a"

    property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")
    property string currentDate: Qt.formatDateTime(new Date(), "dd.MM.yyyy")
    property string selectedUser: userModel.lastUser
    property bool userListOpen: false

    // ─── Фон ───
    Image {
        source: config.background
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
    }

    // ─── Затемняющий градиент ───
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#66000000" }
            GradientStop { position: 0.5; color: "#99000000" }
            GradientStop { position: 1.0; color: "#cc000000" }
        }
    }

    // ─── Виньетка слева ───
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#bb000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // ─── Слой закрытия списка кликом вне ───
    // z:1 — ниже loginForm (z:2), поэтому клики по элементам формы
    // (selector, password, button, dropdown) идут в них, а не сюда
    MouseArea {
        anchors.fill: parent
        enabled: root.userListOpen
        z: 1
        onClicked: root.userListOpen = false
    }

    // ─── Заголовок ───
    Column {
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -110
        spacing: 4
        z: 2

        Text {
            text: "SOLDATIK"
            color: "#ffffff"
            font.pixelSize: 52
            font.bold: true
            font.family: "JetBrainsMono Nerd Font"
            font.letterSpacing: 6
        }

        Rectangle {
            width: 60
            height: 1
            color: "#ffffff"
            opacity: 0.7
        }

        Text {
            text: "L I N U X"
            color: "#a0a0a0"
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
            font.letterSpacing: 6
        }
    }

    // ─── Форма логина ───
    // z:2 — выше closeLayer (z:1), чтобы клики по форме работали
    Item {
        id: loginForm
        z: 2
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 70
        width: 300
        height: 42 + 12 + 42 + 12 + 42

        // ═══════════════════════════════════════════════
        // ВЫБОР ПОЛЬЗОВАТЕЛЯ
        // ═══════════════════════════════════════════════
        Rectangle {
            id: userSelector
            width: parent.width
            height: 42
            color: "#1a1a1a"
            opacity: 0.9
            border.color: root.userListOpen ? "#ffffff" : "#404040"
            border.width: 1

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedUser
                color: "#ffffff"
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"
            }

            // ─── Стрелка ▼ с плавным поворотом ───
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "▼"
                color: "#808080"
                font.pixelSize: 10
                rotation: root.userListOpen ? 180 : 0
                Behavior on rotation {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.userListOpen = !root.userListOpen
            }
        }

        // ═══════════════════════════════════════════════
        // ПАРОЛЬ
        // ═══════════════════════════════════════════════
        Rectangle {
            id: passField
            width: parent.width
            height: 42
            anchors.top: userSelector.bottom
            anchors.topMargin: 12
            color: "#1a1a1a"
            opacity: 0.9
            border.color: passInput.activeFocus ? "#ffffff" : "#404040"
            border.width: 1

            TextInput {
                id: passInput
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                color: "#ffffff"
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"
                echoMode: TextInput.Password
                passwordCharacter: "•"
                verticalAlignment: TextInput.AlignVCenter
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                focus: true

                Text {
                    anchors.fill: parent
                    text: "ПАРОЛЬ"
                    color: "#606060"
                    font.pixelSize: 11
                    font.family: "JetBrainsMono Nerd Font"
                    font.letterSpacing: 2
                    verticalAlignment: Text.AlignVCenter
                    visible: passInput.text === "" && !passInput.activeFocus
                }

                Keys.onReturnPressed: root.doLogin()
                Keys.onEnterPressed:  root.doLogin()
            }
        }

        // ═══════════════════════════════════════════════
        // КНОПКА ВОЙТИ
        // ═══════════════════════════════════════════════
        Rectangle {
            id: loginButton
            width: parent.width
            height: 42
            anchors.top: passField.bottom
            anchors.topMargin: 12
            color: btnMouse.containsMouse ? "#ffffff" : "transparent"
            border.color: "#ffffff"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "В О Й Т И"
                color: btnMouse.containsMouse ? "#000000" : "#ffffff"
                font.pixelSize: 13
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
                font.letterSpacing: 3
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.doLogin()
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        // ═══════════════════════════════════════════════
        // ВЫПАДАЮЩИЙ СПИСОК ПОЛЬЗОВАТЕЛЕЙ
        // z:100 внутри loginForm — поверх пароля и кнопки
        // (loginForm сам z:2 → и dropdown выше closeLayer)
        // ═══════════════════════════════════════════════
        Rectangle {
            id: userDropdown
            visible: root.userListOpen
            anchors.top: userSelector.bottom
            anchors.topMargin: 2
            anchors.left: userSelector.left
            width: userSelector.width
            height: Math.min(userModel.rowCount() * 38 + 2, 220)
            color: "#0f0f0f"
            border.color: "#ffffff"
            border.width: 1
            z: 100

            ListView {
                anchors.fill: parent
                anchors.margins: 1
                model: userModel
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: -1

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 38
                    color: itemMouse.containsMouse ? "#2a2a2a" : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.name
                        color: root.selectedUser === model.name ? "#ffffff" : "#a0a0a0"
                        font.pixelSize: 13
                        font.family: "JetBrainsMono Nerd Font"
                        font.bold: root.selectedUser === model.name
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedUser = model.name
                            root.userListOpen = false
                            passInput.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }

    // ─── © ───
    Text {
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.10
        anchors.top: loginForm.bottom
        anchors.topMargin: 20
        text: "© 2026 SOLDATIK LINUX"
        color: "#404040"
        font.pixelSize: 10
        font.family: "JetBrainsMono Nerd Font"
        font.letterSpacing: 3
        z: 2
    }

    // ─── Часы ───
    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 40
        anchors.topMargin: 40
        spacing: 2
        z: 2

        Text {
            text: root.currentTime
            color: "#ffffff"
            font.pixelSize: 36
            font.bold: true
            font.family: "JetBrainsMono Nerd Font"
            font.letterSpacing: 2
            anchors.right: parent.right
        }

        Text {
            text: root.currentDate
            color: "#808080"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.letterSpacing: 3
            anchors.right: parent.right
        }
    }

    // ─── Обновление часов ───
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentTime = Qt.formatDateTime(new Date(), "HH:mm")
            root.currentDate = Qt.formatDateTime(new Date(), "dd.MM.yyyy")
        }
    }

    // ─── Esc закрывает список (глобально, без фокуса) ───
    Shortcut {
        sequence: "Escape"
        enabled: root.userListOpen
        onActivated: {
            root.userListOpen = false
            passInput.forceActiveFocus()
        }
    }

    // ─── Функция логина ───
    function doLogin() {
        root.userListOpen = false
        sddm.login(root.selectedUser, passInput.text, sessionModel.lastIndex)
    }

    // ─── Обработка неудачного входа ───
    Connections {
        target: sddm
        function onLoginFailed() {
            passInput.text = ""
            passInput.forceActiveFocus()
        }
    }

    // ─── Инициализация ───
    Component.onCompleted: {
        // Первый fallback — если lastUser уже есть, берём его
        if (root.selectedUser === "") {
            trySelectFirstUser()
        }
        passInput.forceActiveFocus()
    }

    // ─── Fallback: если модель ещё пустая, ждём ───
    Timer {
        id: userModelWatcher
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (root.selectedUser !== "") {
                stop()
                return
            }
            if (trySelectFirstUser()) {
                stop()
            }
        }
    }

    function trySelectFirstUser() {
        if (userModel.rowCount() === 0) return false

        var first = userModel.data(userModel.index(0, 0), Qt.DisplayRole)
        if (first) {
            root.selectedUser = first
            return true
        }
        return false
    }
}
