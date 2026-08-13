pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root
    signal toggleMute
    signal setMute(bool muted)
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
    readonly property string iconName: getIconName()
    function getIconName() {
        const volume = root.sink?.audio?.volume ?? 0;
        if (sink?.audio?.muted) {
            return "audio-volume-muted";
        }
        if (volume <= 0.33) {
            return "audio-volume-low";
        } else if (volume <= 0.66) {
            return "audio-volume-medium";
        }
        return "audio-volume-high";
    }
    onToggleMute: {
        if (root.sink) {
            root.sink.audio.muted = !root.sink.audio.muted;
        }
    }
    onSetMute: function (muted) {
        if (root.sink) {
            root.sink.audio.muted = muted;
        }
    }
}
