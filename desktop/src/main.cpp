#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "TelefamDesktopController.hpp"

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Telefam"));
    app.setApplicationName(QStringLiteral("Telefam"));

    TelefamDesktopController controller;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("telefam"), &controller);
    engine.loadFromModule("TelefamDesktop", "Main");

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }
    return app.exec();
}
