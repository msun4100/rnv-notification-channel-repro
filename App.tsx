import React, {useCallback, useEffect, useRef, useState} from 'react';
import {Button, SafeAreaView, StyleSheet, Text, View} from 'react-native';
import Video from 'react-native-video';

const SOURCE = {
  uri: 'https://bitmovin-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
};

// The loop starts on launch so that scripts/repro.sh can drive it without touching the UI.
const AUTO_START = true;
// How long each <Video> stays mounted. A short, random time makes many unmounts land right after
// VideoPlaybackService.registerPlayer() has called startForeground().
const HOLD_MIN_MS = 0;
const HOLD_MAX_MS = 80;
// Pause between an unmount and the next mount.
const GAP_MS = 60;

function App(): React.JSX.Element {
  const [running, setRunning] = useState(AUTO_START);
  const [mounted, setMounted] = useState(false);
  const [cycle, setCycle] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clear = useCallback(() => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
    }
  }, []);

  useEffect(() => {
    if (!running) {
      clear();
      setMounted(false);
      return;
    }
    if (mounted) {
      const hold =
        HOLD_MIN_MS + Math.floor(Math.random() * (HOLD_MAX_MS - HOLD_MIN_MS));
      timer.current = setTimeout(() => setMounted(false), hold);
    } else {
      timer.current = setTimeout(() => {
        setCycle(c => c + 1);
        setMounted(true);
      }, GAP_MS);
    }
    return clear;
  }, [running, mounted, clear]);

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>mount/unmount cycle {cycle}</Text>
      <Button
        title={running ? 'Stop' : 'Start'}
        onPress={() => setRunning(r => !r)}
      />
      <View style={styles.player}>
        {mounted ? (
          <Video
            key={cycle}
            source={SOURCE}
            style={styles.video}
            showNotificationControls
            muted
          />
        ) : null}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {flex: 1, padding: 16, backgroundColor: '#fff'},
  title: {fontSize: 20, marginBottom: 12, color: '#000'},
  player: {height: 220, marginTop: 16, backgroundColor: '#000'},
  video: {flex: 1},
});

export default App;
