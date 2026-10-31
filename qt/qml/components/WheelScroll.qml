import QtQuick

// Mouse-wheel and trackpad scrolling for a Flickable that is not meant to be dragged with the mouse (on a desktop, dragging a list to
// scroll it is unexpected). Put it inside the Flickable, which must have `interactive: false`. It scrolls sideways too when the content
// is wider than the view (a trackpad swipe, or Shift with a mouse wheel).
WheelHandler {
    // the Flickable to scroll (a handler declared inside one is attached to its content, not to the Flickable itself, so it is named)
    required property Flickable view

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        // a trackpad gives pixels; a wheel gives notches (120 units each)
        let dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * Theme.wheelStep
        let dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 120 * Theme.wheelStep
        if ((event.modifiers & Qt.ShiftModifier) && dx === 0) { dx = dy; dy = 0 }     // (macOS already turns Shift+wheel sideways)
        const top = view.originY
        const bottom = Math.max(top, view.originY + view.contentHeight - view.height)
        view.contentY = Math.max(top, Math.min(bottom, view.contentY - dy))
        if (view.contentWidth > view.width) {
            const left = view.originX
            const right = Math.max(left, view.originX + view.contentWidth - view.width)
            view.contentX = Math.max(left, Math.min(right, view.contentX - dx))
        }
        event.accepted = true
    }
}
