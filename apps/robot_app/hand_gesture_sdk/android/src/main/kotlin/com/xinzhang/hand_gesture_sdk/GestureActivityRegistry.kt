package com.xinzhang.hand_gesture_sdk

internal object GestureActivityRegistry {
    @Volatile
    var currentActivity: GestureActivity? = null
}
