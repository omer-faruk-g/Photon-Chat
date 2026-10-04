{{flutter_js}}
{{flutter_build_config}}

// Çizim motoru (CanvasKit) Google CDN yerine uygulamanın kendi sunucusundan yüklenir:
// açılış üçüncü taraf bir sunucuya bağlı kalmaz ve kullanıcının IP'si Google'a gitmez.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
