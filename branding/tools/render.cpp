// Renders branding/icon.svg into the apps' icon files. Built and run by branding/export.sh.
//
//   render icon.svg out.png <size> square     opaque, full bleed: iOS and watchOS (the system rounds the corners itself)
//   render icon.svg out.png <size> macos      the macOS shape: a rounded square inset in a transparent canvas, as macOS icons are
//   render icon.svg out.png sheet             a preview of the sizes on light and dark backgrounds
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QSvgRenderer>

static QImage render(QSvgRenderer &svg, int size, const QString &shape)
{
    QImage img(size, size, shape == "square" ? QImage::Format_RGB32 : QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    QRectF area(0, 0, size, size);
    if (shape == "macos") {
        // Apple's macOS grid: an 824-unit rounded square (corner radius 185) centred in 1024
        area = QRectF(size * 100 / 1024.0, size * 100 / 1024.0, size * 824 / 1024.0, size * 824 / 1024.0);
        QPainterPath clip;
        clip.addRoundedRect(area, size * 185 / 1024.0, size * 185 / 1024.0);
        p.setClipPath(clip);
    } else if (shape == "rounded") {
        QPainterPath clip;
        clip.addRoundedRect(area, size * 0.2237, size * 0.2237);
        p.setClipPath(clip);
    }
    svg.render(&p, area);
    return img;
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 4)
        return 2;
    QSvgRenderer svg(QString::fromLocal8Bit(argv[1]));
    if (!svg.isValid())
        return 2;
    if (QString(argv[3]) == "sheet") {
        const QList<int> sizes = { 512, 180, 120, 87, 60, 40, 29 };
        QImage sheet(1500, 1240, QImage::Format_ARGB32_Premultiplied);
        QPainter p(&sheet);
        p.fillRect(0, 0, 1500, 620, QColor("#f2f2f7"));
        p.fillRect(0, 620, 1500, 620, QColor("#1c1c1e"));
        for (int row = 0; row < 2; row++) {
            int x = 40;
            for (int s : sizes) {
                p.drawImage(x, row * 620 + (620 - s) / 2, render(svg, s, "rounded"));
                x += s + 40;
            }
        }
        p.end();
        return sheet.save(argv[2]) ? 0 : 1;
    }
    return render(svg, atoi(argv[3]), argc > 4 ? argv[4] : "square").save(argv[2]) ? 0 : 1;
}
