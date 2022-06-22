import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive/hive.dart';
import 'package:source_gen/source_gen.dart';

final _hiveFieldChecker = const TypeChecker.fromRuntime(HiveField);
final _hiveVersionFieldChecker =
    const TypeChecker.fromRuntime(HiveVersionField);

class HiveFieldInfo {
  HiveFieldInfo(this.index, this.defaultValue, this.versioningFlow);

  final int index;
  final DartObject? defaultValue;
  final Map<int, DartType> versioningFlow;
}

HiveFieldInfo? getHiveFieldAnn(Element element) {
  var hiveFieldObj = _hiveFieldChecker.firstAnnotationOfExact(element);
  var hiveVersionFieldsObj = _hiveVersionFieldChecker
      .annotationsOfExact(element, throwOnUnresolved: false);
  Map<int, DartType> versioningFlow = {};
  if (hiveFieldObj == null) return null;
  if (hiveVersionFieldsObj.isNotEmpty) {
    hiveVersionFieldsObj.forEach(
      (hiveVersionField) {
        versioningFlow[hiveVersionField.getField('version')!.toIntValue()!] =
            (hiveVersionField.getField('type')!).toTypeValue() ??
                (hiveVersionField.getField('type')!).type!;
      },
    );
  }

  return HiveFieldInfo(
    hiveFieldObj.getField('index')!.toIntValue()!,
    hiveFieldObj.getField('defaultValue'),
    versioningFlow,
  );
}

bool isLibraryNNBD(Element element) {
  final dartVersion = element.library!.languageVersion.effective;
  // Libraries with the dart version >= 2.12 are nnbd
  if (dartVersion.major >= 2 && dartVersion.minor >= 12) {
    return true;
  } else {
    return false;
  }
}

Iterable<ClassElement> getTypeAndAllSupertypes(ClassElement cls) {
  var types = <ClassElement>{};
  types.add(cls);
  types.addAll(cls.allSupertypes.map((it) => it.element));
  return types;
}

void check(bool condition, Object error) {
  if (!condition) {
    // ignore: only_throw_errors
    throw error;
  }
}
