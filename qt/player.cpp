#include "player.h"
#include "settings.h"

#include <QAudio>
#include <QQmlEngine>
#include <QRandomGenerator>
#include <QUrl>

#include <algorithm>

namespace {

QUrl trackUrl(const QVariantMap &track)
{
    const QString url = track.value("url").toString();
    return url.isEmpty() ? QUrl::fromLocalFile(track.value("path").toString()) : QUrl(url);
}

} // namespace

Player::Player(Settings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    m_player.setAudioOutput(&m_output);
    applyVolume();
    connect(m_settings, &Settings::volumeChanged, this, &Player::applyVolume);

    connect(&m_player, &QMediaPlayer::playbackStateChanged, this, &Player::playingChanged);
    connect(&m_player, &QMediaPlayer::positionChanged, this, &Player::positionChanged);
    connect(&m_player, &QMediaPlayer::durationChanged, this, &Player::durationChanged);
    connect(&m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        if (status == QMediaPlayer::BufferedMedia && m_failures > 0)
            m_failures = 0;
        if (status == QMediaPlayer::EndOfMedia)
            advance(false);
    });
    connect(&m_player, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error, const QString &message) {
        m_error = tr("Could not play “%1”: %2").arg(current().value("title").toString(), message);
        emit errorChanged();
        qWarning().noquote() << "legato:" << m_error;
        // move on, unless nothing in the list will play
        if (++m_failures < m_queue.size())
            advance(false);
        else
            m_player.stop();
    });
}

Player *Player::create(QQmlEngine *qml, QJSEngine *)
{
    return new Player(qml->singletonInstance<Settings *>("App", "Settings"));
}

void Player::applyVolume()
{
    // the slider is in steps the ear hears as even; the output wants a linear gain
    m_output.setVolume(QAudio::convertVolume(m_settings->volume() / 100.0, QAudio::LogarithmicVolumeScale, QAudio::LinearVolumeScale));
}

QVariantMap Player::current() const
{
    return m_step >= 0 && m_step < m_order.size() ? m_queue.value(m_order[m_step]).toMap() : QVariantMap();
}

qreal Player::duration() const
{
    // the tags' length when there is one: the decoder's guess for some formats (Opus) can be seconds out
    const qreal tagged = current().value("duration").toDouble();
    return tagged > 0 ? tagged : m_player.duration() / 1000.0;
}

void Player::play(const QVariantMap &track)
{
    playList({ track }, 0);
}

void Player::playList(const QVariantList &tracks, int index)
{
    m_queue = tracks;
    m_failures = 0;
    emit queueChanged();
    if (m_queue.isEmpty()) {
        stop();
        return;
    }
    reorder(qBound(0, index, int(m_queue.size()) - 1));
    load(m_step, true);
}

void Player::reorder(int first)
{
    m_order.clear();
    for (int i = 0; i < m_queue.size(); i++)
        m_order << i;
    if (m_shuffle) {
        // the chosen track first, the rest in a random order after it
        m_order.removeOne(first);
        std::shuffle(m_order.begin(), m_order.end(), *QRandomGenerator::global());
        m_order.prepend(first);
        m_step = 0;
    } else {
        m_step = first;
    }
}

void Player::load(int step, bool autoplay)
{
    if (m_order.isEmpty())
        return;
    m_step = qBound(0, step, int(m_order.size()) - 1);
    if (!m_error.isEmpty()) {
        m_error.clear();
        emit errorChanged();
    }
    m_player.setSource(trackUrl(current()));
    emit currentChanged();
    emit durationChanged();
    if (autoplay)
        m_player.play();
}

void Player::advance(bool byHand)
{
    if (m_order.isEmpty())
        return;
    // repeating one track: it starts again when it ends, but next still moves on
    if (m_repeat == RepeatOne && !byHand) {
        m_player.setPosition(0);
        m_player.play();
        return;
    }
    if (m_step + 1 < m_order.size()) {
        load(m_step + 1, true);
        return;
    }
    // past the end of the list
    if (m_repeat != RepeatOff) {
        if (m_shuffle) {
            // a new order for the next time round, which does not start with the track just heard
            const int last = m_order.last();
            int first = last;
            while (m_queue.size() > 1 && first == last)
                first = QRandomGenerator::global()->bounded(int(m_queue.size()));
            reorder(first);
        }
        load(0, true);
        return;
    }
    // the end: back to the first track, stopped, as a CD player does
    load(0, false);
    m_player.stop();
}

void Player::next()
{
    m_failures = 0;
    advance(true);
}

void Player::previous()
{
    if (m_order.isEmpty())
        return;
    if (m_player.position() > 3000 || (m_step == 0 && m_repeat == RepeatOff)) {
        m_player.setPosition(0);
        return;
    }
    const bool wasPlaying = playing();
    load(m_step > 0 ? m_step - 1 : int(m_order.size()) - 1, wasPlaying);
}

void Player::toggle()
{
    if (playing())
        pause();
    else
        resume();
}

void Player::pause()
{
    m_player.pause();
}

void Player::resume()
{
    if (!m_order.isEmpty())
        m_player.play();
}

void Player::stop()
{
    m_player.stop();
    m_player.setSource(QUrl());
    m_queue.clear();
    m_order.clear();
    m_step = -1;
    emit queueChanged();
    emit currentChanged();
    emit durationChanged();
}

void Player::seek(qreal seconds)
{
    m_player.setPosition(qint64(qMax<qreal>(0, seconds) * 1000));
}

void Player::setShuffle(bool on)
{
    if (on == m_shuffle)
        return;
    m_shuffle = on;
    // keep playing what is playing; only what comes after it changes
    if (!m_order.isEmpty()) {
        reorder(m_order[m_step]);
    }
    emit shuffleChanged();
}

void Player::setRepeat(Repeat repeat)
{
    if (repeat == m_repeat)
        return;
    m_repeat = repeat;
    emit repeatChanged();
}

void Player::cycleRepeat()
{
    setRepeat(m_repeat == RepeatOff ? RepeatAll : m_repeat == RepeatAll ? RepeatOne : RepeatOff);
}
