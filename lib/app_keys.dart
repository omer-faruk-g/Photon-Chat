import 'package:flutter/material.dart';

/// RootGate'in State'ine dışarıdan (örn. hesap silindikten sonra) erişip
/// reload() çağırabilmek için global anahtar.
///
/// Tip burada `State<StatefulWidget>` olarak tutulur ki bu dosya
/// root_gate.dart'ı import etmek zorunda kalmasın ve
/// main.dart <-> screens/contacts_screen.dart <-> root_gate.dart arasında
/// döngüsel import oluşmasın. reload() çağrısı dynamic üzerinden yapılır.
final rootGateKey = GlobalKey<State<StatefulWidget>>();
