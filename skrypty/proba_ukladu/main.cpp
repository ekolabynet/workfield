// WorkField 24.08.2026 — URUCHOM OKNO I ZMIERZ, zamiast czytac kod.
//
// Trzy razy z rzedu zepsulem rozmiar tego samego panelu i za kazdym razem
// "naprawialem" go czytaniem QML-a. Oba sita (skladnia, struktura) przepuszczaly
// go bez slowa, bo zadne nie liczy pikseli. Ten program laduje plik QML na
// platformie offscreen i WYPISUJE geometrie: czy zawartosc miesci sie w oknie
// i czy cokolwiek ma zerowa wysokosc.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QTextStream>
#include <QTimer>

static QTextStream out(stdout);

void obejdz(QQuickItem *it, int gl, QQuickItem *korzen)
{
  if (!it) return;
  const QString typ = QString::fromUtf8(it->metaObject()->className()).section("_QML", 0, 0);
  const QString id = it->objectName();
  const bool zero = it->height() <= 0.5 || it->width() <= 0.5;
  const bool wystaje = korzen && (it->width() > korzen->width() + 1);
  if (gl <= 3 || zero || wystaje) {
    out << QString(gl * 2, ' ')
        << typ << (id.isEmpty() ? "" : " [" + id + "]")
        << QString("  %1x%2").arg(it->width(), 0, 'f', 0).arg(it->height(), 0, 'f', 0)
        << QString("  implicit %1x%2").arg(it->implicitWidth(), 0, 'f', 0).arg(it->implicitHeight(), 0, 'f', 0)
        << (zero ? "   <-- ZEROWY" : "")
        << (wystaje ? "   <-- SZERSZY NIZ OKNO" : "")
        << "\n";
  }
  const auto dzieci = it->childItems();
  for (QQuickItem *d : dzieci) obejdz(d, gl + 1, korzen);
}

int main(int argc, char *argv[])
{
  QGuiApplication app(argc, argv);
  if (argc < 2) { out << "Uzycie: proba_ukladu plik.qml\n"; return 2; }

  QQmlApplicationEngine silnik;
  silnik.addImportPath(QStringLiteral("/tmp/proba_ukladu/atrapy"));

  // Atrapa okna glownego jako wlasciwosc kontekstu — panel odwoluje sie do
  // `mainWindow.contentItem` i `mainWindow.width`, a te nazwy w prawdziwej
  // aplikacji sa identyfikatorami z QgisMobileapp.qml.
  QQmlComponent okno(&silnik, QUrl::fromLocalFile("/tmp/proba_ukladu/OknoGlowne.qml"));
  QObject *oknoObj = okno.create();
  if (!oknoObj) {
    for (const auto &b : okno.errors()) out << "ATRAPA OKNA: " << b.toString() << "\n";
    return 1;
  }
  silnik.rootContext()->setContextProperty("mainWindow", oknoObj);
  silnik.rootContext()->setContextProperty("platformUtilities", oknoObj);
  silnik.rootContext()->setContextProperty("settings", oknoObj);
  silnik.rootContext()->setContextProperty("dashBoard", oknoObj);
  QQmlComponent skladnik(&silnik, QUrl::fromLocalFile(argv[1]));
  if (skladnik.isError()) {
    for (const auto &b : skladnik.errors()) out << "BLAD: " << b.toString() << "\n";
    return 1;
  }
  QObject *o = skladnik.create();
  if (!o) { out << "Nie da sie utworzyc obiektu\n"; return 1; }

  QQuickItem *korzen = qobject_cast<QQuickItem *>(o);
  if (!korzen) {
    // Popup nie jest Itemem — bierzemy jego contentItem.
    korzen = o->property("contentItem").value<QQuickItem *>();
    const qreal w = o->property("width").toReal();
    const qreal h = o->property("height").toReal();
    out << "korzen to Popup:  " << w << "x" << h << "\n";
    if (korzen) { korzen->setWidth(w); korzen->setHeight(h); }
  }
  if (!korzen) { out << "Brak contentItem\n"; return 1; }
  QCoreApplication::processEvents();
  out << "\n=== drzewo (pokazuje 3 poziomy oraz KAZDY element zerowy albo za szeroki)\n";
  obejdz(korzen, 0, korzen);
  out.flush();
  return 0;
}
