// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Telefam",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "TelefamApp", targets: ["TelefamApp"])
    ],
    targets: [
        .target(
            name: "CTelefamCore",
            path: "../core",
            sources: [
                "src/telefam_crypto.cpp",
                "src/telefam_engine.cpp"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-std=c++20"])
            ]
        ),
        .target(
            name: "TelefamApp",
            dependencies: ["CTelefamCore"],
            path: "Telefam",
            exclude: ["Bridge/module.modulemap"],
            resources: [
                .process("Resources")
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
