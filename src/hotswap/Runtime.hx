package hotswap;

class Runtime {
  @:keep static final self = Type.resolveClass('hotswap.Runtime');
  static function patch(oldClasses:Dict, oldEnums:Dict) {
    var newClasses:Dict = untyped $hxClasses,
        newEnums:Dict = untyped $hxEnums;

    for (k => v in newEnums)
      oldEnums[k] = v;


  }
}

private typedef Dict = haxe.DynamicAccess<Dynamic>;