package hotswap;

import haxe.ds.Option;
import haxe.DynamicAccess as Dict;
import js.Syntax.code as __js;
import js.Lib.*;

class Runtime {
  static var last = '';

  static public function patch(source:String) {
    if (source == null || source == '' || source == last) return;
    var old = root;
    __js('var hxPatch = null');
    eval(source);
    __js('hx = hxPatch');
    doPatch(old);
    last = source;
  }

  static public final FIRST_LOAD = {
    var isFirst:Bool = __js('typeof hxPatch === "undefined"');
    if (!isFirst)
      __js('hxPatch = hx');

    isFirst;
  }

  static function __init__() {
    var meta:Dict<Array<String>> = untyped hotswapmeta.closures;
    for (n => closures in meta) {
      var proto = root[n].prototype;

      for (k in closures) {
        var alias = 'hotreload.$k';
        proto[alias] = proto[k];
        proto[k] = proto.forward(alias);
      }

    }
  }

  static function boot()
    for (n => c in root) bootClass(c);

  static var root(get, never):Root;
    static function get_root():Root
      return __js('hx');

  static function bootClass(c:Cls, ?old:Cls)
    if (c.onHotswapLoad != null)
      c.onHotswapLoad(old == null);

  static function getStatics(c:Cls)
    return meta(if (c == null) {} else haxe.rtti.Meta.getStatics(c), 'hotreload.persist');

  static function meta(meta:Dynamic<Dynamic<Array<Dynamic>>>, name) {
    var ret = new Dict<Bool>();
    for (f in Reflect.fields(meta))
      ret[f] = Reflect.hasField(Reflect.field(meta, f), name);
    return ret;
  }

  static function updateStatics(c:Cls, ?old:Cls) {
    var isOld = getStatics(old).exists;

    for (f in getStatics(c).keys())
      if (isOld(f))
        Reflect.setField(c, f, Reflect.field(old, f));
  }

  static function rewireProto(c:Cls, ?old:Cls) {
    var proto = c.prototype;

    if (old != null) {
      var oldProto = old.prototype;
      for (k => v in oldProto)
        if (Reflect.isFunction(v))
          switch proto[k] {
            case null:
            case Reflect.isFunction(_) => true:
              oldProto[k] = proto.forward(k);
            default:
          }
        else {
          // TODO: should anything happen here?
        }
    }
  }

  static function doPatch(oldRoot:Root) {

    var newRoot = root;

    for (k => v in oldRoot)
      if (v.onHotswapUnload)
        v.onHotswapUnload(newRoot.exists(k));

    for (n => c in newRoot) {
      rewireProto(c, oldRoot[n]);
      updateStatics(c, oldRoot[n]);
    }

    for (n => c in newRoot)
      bootClass(c, oldRoot[n]);
  }
}

private typedef Root = haxe.DynamicAccess<Cls>;

@:forward
private abstract Cls(Dynamic) {
  public var prototype(get, never):Proto;
    inline function get_prototype():Proto
      return this.prototype;
}

@:forward
private abstract Proto(haxe.DynamicAccess<Dynamic>) {
  public function forward(name)
    return function () {
      return this[name].apply(nativeThis, __js('arguments'));
    }

  @:op([]) public inline function get(name)
    return this.get(name);

  @:op([]) public inline function set(name, value)
    return this.set(name, value);

}