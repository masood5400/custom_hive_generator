import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/extensions.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

import 'type_helper.dart';

class ClassBuilder extends Builder {
  ClassBuilder(
    ClassElement cls,
    List<AdapterField> getters,
    List<AdapterField> setters,
    int hiveVersion,
  ) : super(cls, getters, setters, hiveVersion);

  var hiveListChecker = const TypeChecker.fromRuntime(HiveList);
  var listChecker = const TypeChecker.fromRuntime(List);
  var mapChecker = const TypeChecker.fromRuntime(Map);
  var setChecker = const TypeChecker.fromRuntime(Set);
  var iterableChecker = const TypeChecker.fromRuntime(Iterable);
  var uint8ListChecker = const TypeChecker.fromRuntime(Uint8List);
  var stringChecker = const TypeChecker.fromRuntime(String);
  var boolChecker = const TypeChecker.fromRuntime(bool);
  var doubleChecker = const TypeChecker.fromRuntime(double);
  var intChecker = const TypeChecker.fromRuntime(int);

  @override
  String buildRead() {
    var constr = cls.constructors.firstOrNullWhere((it) => it.name.isEmpty);
    check(constr != null, 'Provide an unnamed constructor.');

    // The remaining fields to initialize.
    var fields = setters.toList();

    // Empty classes
    if (constr!.parameters.isEmpty && fields.isEmpty) {
      return 'return ${cls.name}();';
    }

    var code = StringBuffer();
    code.writeln('''
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++)
        reader.readByte(): reader.read(),
    };
    int? currentVersion = fields[0] as int?;
    return ${cls.name}(
    ''');

    for (var param in constr.parameters) {
      var field = fields.firstOrNullWhere((it) => it.name == param.name);
      // Final fields
      field ??= getters.firstOrNullWhere((it) => it.name == param.name);
      if (field != null) {
        if (param.isNamed) {
          code.write('${param.name}: ');
        }
        code.write(_value(field));

        code.writeln(',');
        fields.remove(field);
      }
    }

    code.writeln(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var field in fields) {
      code.write('..${field.name} = ');
      code.writeln(_value(field));
    }

    code.writeln(';');
    code.writeln('}');
    fields = setters.toList();
    for (var field in fields) {
      if (field.versioningFlow.isNotEmpty) {
        code.writeln();
        code.writeln(_migrationMethodGenerator(field));
      }
    }

    return code.toString();
  }

  String _migrationMethodGenerator(AdapterField field) {
    var migrateCode = StringBuffer();
    var displayType = field.type.getDisplayString(withNullability: false);
    migrateCode.write(
        '''$displayType? ${field.name}Migration({dynamic field, int currentVersion = 1}) {
              dynamic resultValue = field;
              for (var i = currentVersion; i < lastVersion; i++) {
                switch (i) {''');
    field.versioningFlow.forEach((key, DartType value) {
      migrateCode.writeln('''case $key:
          ${_migrationCastFlow(version: key, type: value, field: field)}
        break;''');
    });
    migrateCode.writeln('''default:
      }
      }''');
    migrateCode
        .writeln('''${_migrationCastFlow(type: field.type, field: field)}''');
    migrateCode.writeln('return resultValue as $displayType?;');
    migrateCode.writeln('}');
    return migrateCode.toString();
  }

  String _migrationCastFlow({
    int? version,
    required DartType type,
    required AdapterField field,
  }) {
    var currentSuffix = _suffixFromType(type);
    return _findTypeFunction(type, other: () {
      return '''resultValue = ${cls.name}().get${field.name.capitalize()}(resultValue ,version: ${version != null ? version : 'lastVersion'});''';
    }, nonIterable: () {
      return '''resultValue = CastUtils().cast<${_displayString(type)}>(currentValue: resultValue);''';
    });
  }

  String _findTypeFunction(DartType type,
      {required String Function() nonIterable,
      required String Function() other}) {
    if ((stringChecker.isAssignableFromType(type) ||
        boolChecker.isAssignableFromType(type) ||
        intChecker.isAssignableFromType(type) ||
        doubleChecker.isAssignableFromType(type))) {
      return nonIterable();
    } else {
      return other();
    }
  }

  String _value(AdapterField field) {
    String value;
    if (field.versioningFlow.isNotEmpty) {
      value = _migrationCast(field);
    } else {
      value = _cast(field.type, 'fields[${field.index + 1}]');
    }
    if (field.defaultValue?.isNull != false) return value;
    return 'fields[${field.index + 1}] == null ? ${constantToString(field.defaultValue!)} : $value';
  }

  String _migrationCast(AdapterField field) {
    return '''${field.name}Migration(field: fields[${field.index + 1}], currentVersion: currentVersion ?? 1)''';
  }

  String _cast(DartType type, String variable, {String? nameOfVariable}) {
    var suffix = _suffixFromType(type);
    if (hiveListChecker.isAssignableFromType(type)) {
      return '($variable as HiveList$suffix)$suffix.castHiveList()';
    } else if (iterableChecker.isAssignableFromType(type) &&
        !isUint8List(type)) {
      return '($variable as List$suffix)${_castIterable(type)}';
    } else if (mapChecker.isAssignableFromType(type)) {
      return '($variable as Map$suffix)${_castMap(type)}';
    } else if ((stringChecker.isAssignableFromType(type) ||
        boolChecker.isAssignableFromType(type) ||
        intChecker.isAssignableFromType(type) ||
        doubleChecker.isAssignableFromType(type))) {
      return '$variable as ${_displayString(type)}';
    } else {
      if (nameOfVariable != null) {
        return '${_displayString(type)}.fromJson({\'$nameOfVariable\': $variable});';
      } else if (_displayString(type).startsWith('Color')) {
        return 'Color($variable)';
      } else {
        return '$variable as ${_displayString(type)}';
      }
    }
  }

  bool isMapOrIterable(DartType type) {
    return iterableChecker.isAssignableFromType(type) ||
        mapChecker.isAssignableFromType(type);
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments.first;
    var suffix = _accessorSuffixFromType(type);
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var cast = '';
      // Using assignable because List? is not exactly List
      if (listChecker.isAssignableFromType(type)) {
        cast = '.toList()';
        // Using assignable because Set? is not exactly Set
      } else if (setChecker.isAssignableFromType(type)) {
        cast = '.toSet()';
      }
      // The suffix is not needed with nnbd on $cast becauuse it short circuits,
      // otherwise it is needed.
      var castWithSuffix = isLibraryNNBD(cls) ? '$cast' : '$suffix$cast';
      return '$suffix.map((dynamic e)=> ${_cast(arg, 'e')})$castWithSuffix';
    } else {
      return '$suffix.cast<${_displayString(arg)}>()';
    }
  }

  String _castMap(DartType type) {
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    var suffix = _accessorSuffixFromType(type);
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '$suffix.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '$suffix.cast<${_displayString(arg1)}, '
          '${_displayString(arg2)}>()';
    }
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${getters.length + 1})');
    code.writeln('..writeByte(0)');
    code.writeln('..write($hiveVersion)');
    for (var field in getters) {
      var value = _convertIterable(field.type, field);
      code.writeln('''
      ..writeByte(${field.index + 1})
      ..write($value)''');
    }
    code.writeln(';');

    return code.toString();
  }

  String _convertIterable(DartType type, AdapterField accessor) {
    if (listChecker.isAssignableFromType(type)) {
      return 'obj.${accessor.name}';
    } else
    // Using assignable because Set? and Iterable? are not exactly Set and
    // Iterable
    if (setChecker.isAssignableFromType(type) ||
        iterableChecker.isAssignableFromType(type)) {
      var suffix = _accessorSuffixFromType(type);
      return '$accessor$suffix.toList()';
    } else {
      return _displayString(accessor.type).startsWith('Color')
          ? 'obj.${accessor.name}?.value'
          : 'obj.${accessor.name}';
    }
  }
}

extension _FirstOrNullWhere<T> on Iterable<T> {
  T? firstOrNullWhere(bool Function(T) predicate) {
    for (var it in this) {
      if (predicate(it)) {
        return it;
      }
    }
    return null;
  }
}

/// Suffix to use when accessing a field in [type].
/// $variable$suffix.field
String _accessorSuffixFromType(DartType type) {
  if (type.nullabilitySuffix == NullabilitySuffix.star) {
    return '?';
  }
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    return '?';
  }
  return '';
}

/// Suffix to use when casting a value to [type].
/// $variable as $type$suffix
String _suffixFromType(DartType type) {
  if (type.nullabilitySuffix == NullabilitySuffix.star) {
    return '';
  }
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    return '?';
  }
  return '';
}

String _displayString(DartType e) {
  var suffix = _suffixFromType(e);
  return '${e.getDisplayString(withNullability: false)}$suffix';
}
