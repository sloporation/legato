#pragma once

#include <QAudioOutput>
#include <QMediaPlayer>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;
class Settings;

// Plays music, for QML as the `Player` singleton. The rest of the app only hands it things to play:
//
//   Player.play(track)                 one track
//   Player.playList(tracks, index)     a list (the songs as sorted on screen, an album, a playlist), starting at index
//
// A track is a map with a `path` (a local file) or a `url`; the rest of it (title, artist, …) is passed through as `current` for the
// now-playing bar. The player owns what happens next: the order (shuffle), going round again (repeat the list or the track), and
// moving on when a track ends or can't be played.
class Player : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap current READ current NOTIFY currentChanged)       // {} when nothing is loaded
    Q_PROPERTY(QVariantList queue READ queue NOTIFY queueChanged)            // the list as it was given (not shuffled)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(qreal position READ position NOTIFY positionChanged)          // seconds
    Q_PROPERTY(qreal duration READ duration NOTIFY durationChanged)          // seconds
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(Repeat repeat READ repeat WRITE setRepeat NOTIFY repeatChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)                // why the last track could not be played, or ""
public:
    enum Repeat { RepeatOff, RepeatAll, RepeatOne };
    Q_ENUM(Repeat)

    explicit Player(Settings *settings, QObject *parent = nullptr);
    static Player *create(QQmlEngine *qml, QJSEngine *js);

    QVariantMap current() const;
    QVariantList queue() const { return m_queue; }
    bool playing() const { return m_player.playbackState() == QMediaPlayer::PlayingState; }
    qreal position() const { return m_player.position() / 1000.0; }
    qreal duration() const;
    bool shuffle() const { return m_shuffle; }
    void setShuffle(bool on);
    Repeat repeat() const { return m_repeat; }
    void setRepeat(Repeat repeat);
    QString error() const { return m_error; }

    Q_INVOKABLE void play(const QVariantMap &track);
    Q_INVOKABLE void playList(const QVariantList &tracks, int index = 0);
    Q_INVOKABLE void toggle();          // play/pause
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void stop();            // and forget the list
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();        // back to the start of the track, or (near its start) the one before
    Q_INVOKABLE void seek(qreal seconds);
    Q_INVOKABLE void cycleRepeat();     // off → all → one → off, as the button does

signals:
    void currentChanged();
    void queueChanged();
    void playingChanged();
    void positionChanged();
    void durationChanged();
    void shuffleChanged();
    void repeatChanged();
    void errorChanged();

private:
    void reorder(int first);            // the order to play the queue in, starting with the queue's track `first`
    void load(int step, bool autoplay); // the track at m_order[step]
    void advance(bool byHand);          // the track ended (or failed), or next() was pressed
    void applyVolume();

    Settings *m_settings;
    QMediaPlayer m_player;
    QAudioOutput m_output;
    QVariantList m_queue;
    QList<int> m_order;                 // indexes into m_queue, in playing order
    int m_step = -1;                    // where we are in m_order
    bool m_shuffle = false;
    Repeat m_repeat = RepeatOff;
    QString m_error;
    int m_failures = 0;                 // tracks in a row that could not be played: stop when it is every one of them
};
