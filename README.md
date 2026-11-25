# react-native-video: "Bad notification for startForeground" from `VideoPlaybackService`

Reproduction for [TheWidlarzGroup/react-native-video#5234](https://github.com/TheWidlarzGroup/react-native-video/issues/5234).

- react-native 0.78.3 (new architecture), react-native-video 6.19.3
- Tested on an Android 12 (API 31) arm64 emulator

## What the app does

`App.tsx` mounts `<Video showNotificationControls />`, unmounts it after 0–80 ms, waits 60 ms, and repeats. Each cycle starts `VideoPlaybackService`, registers the player (which calls `startForeground()`), and stops the service again. `VideoPlaybackService.onDestroy()` then deletes the notification channel.

## The problem

`startForeground()` returns before Android has looked at the notification. The lookup of the notification channel happens later, in a runnable that system_server posts to its `ActivityManager` handler thread ([`ServiceRecord.postNotification()`](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r1/services/core/java/com/android/server/am/ServiceRecord.java#1215)). If the channel is gone by then, the runnable throws `invalid channel for service notification` and system_server crashes the app with `Bad notification for startForeground`. On Android 13 and later the exception is `CannotPostForegroundServiceNotificationException`. The app is crashed even when the service is already being destroyed.

So when a service instance is stopped shortly after one of its `startForeground()` calls, the channel deletion in `onDestroy()` races against that runnable.

## Run it

```sh
npm install
npm start                      # Metro
npx react-native run-android   # in a second terminal
```

The loop starts when the app opens.

### On an idle emulator: no crash

In my runs the channel was deleted as early as 5 ms after the last `startForeground()`, and the system posted the notification within about 1 ms. 561 mount/unmount cycles gave no crash.

### With the handler thread delayed: crash within a second

`scripts/repro.sh` freezes the `ActivityManager` handler thread of system_server for 150 ms out of every 210 ms. This stands in for a busy device, where that thread is sometimes late. It needs a rooted emulator: use a "Google APIs" system image, not "Google Play".

```sh
adb reverse tcp:8081 tcp:8081
./scripts/repro.sh
```

```
system_server pid 530, ActivityManager handler thread tid 579
Waiting 8 s for the app to load its bundle and start mounting/unmounting <Video>...

Result: CRASH after 1 s (service start commands seen: 46)

W/ActivityManager(  530): Error showing notification for service
W/ActivityManager(  530): java.lang.RuntimeException: invalid channel for service notification: null
W/ActivityManager(  530): 	at com.android.server.am.ServiceRecord$1.run(ServiceRecord.java:1019)
E/AndroidRuntime(22758): FATAL EXCEPTION: main
E/AndroidRuntime(22758): android.app.RemoteServiceException: Bad notification for startForeground
```

## Results

| Library                                                                         | Handler thread | Result                                                 |
| ------------------------------------------------------------------------------- | -------------- | ------------------------------------------------------ |
| 6.19.3                                                                          | not delayed    | no crash in 561 cycles                                 |
| 6.19.3                                                                          | delayed        | crash within 1 s in 6 of 6 runs                        |
| 6.19.3 + channel created again before `startForeground()` in `registerPlayer()` | delayed        | crash within 1 s in 5 of 5 runs                        |
| 6.19.3 + `fix-candidate/keep-notification-channel.patch`                        | delayed        | no crash in 6 runs (3.5 minutes, 1,772 service starts) |

Creating the channel again before the call does not help, because the deletion comes after the call.

## Fix candidate

`fix-candidate/keep-notification-channel.patch` removes the `deleteNotificationChannel()` call from `VideoPlaybackService.onDestroy()`.

```sh
patch -p0 < fix-candidate/keep-notification-channel.patch      # apply
npx react-native run-android
./scripts/repro.sh 60
patch -p0 -R < fix-candidate/keep-notification-channel.patch   # revert
```
