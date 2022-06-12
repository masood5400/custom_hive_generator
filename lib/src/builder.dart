import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

class AdapterField {
  final int index;
  final String name;
  final DartType type;
  final DartObject? defaultValue;
  final Map<int, DartType> versioningFlow;

  AdapterField(
      this.index, this.name, this.type, this.defaultValue, this.versioningFlow);
}

abstract class Builder {
  final ClassElement cls;
  final List<AdapterField> getters;
  final List<AdapterField> setters;
  final int hiveVersion;

  Builder(this.cls, this.getters,
      [this.setters = const <AdapterField>[], this.hiveVersion = 1]);

  String buildRead();

  String buildWrite();
}
