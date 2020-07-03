package hotswap;

import haxe.ds.Option;
import haxe.DynamicAccess as Dict;
import js.Syntax.code as __js;

class Runtime {
  static var last = '';

  static public function patch(source:String) {
    if (source == null || source == '' || source == last) return;
    var old = getRoot();
    __js('var hxPatch = null');
    js.Lib.eval(source);
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

  static function boot() {
    getRoot().crawl(c -> bootProto(c));
    getRoot().crawl(c -> bootClass(c));
  }

  static function getRoot():Node
    return __js('hx');

  static function bootClass(c:Dynamic, ?old:Dynamic)
    if (c.onHotswapLoad != null)
      c.onHotswapLoad(old == null);

  static function getStatics(c:Dynamic)
    return meta(if (c == null) {} else haxe.rtti.Meta.getStatics(c), 'hotreload.persist');

  static function meta(meta:Dynamic<Dynamic<Array<Dynamic>>>, name) {
    var ret = new Dict<Bool>();
    for (f in Reflect.fields(meta))
      ret[f] = Reflect.hasField(Reflect.field(meta, f), name);
    return ret;
  }

  static function updateStatics(c:Dynamic, ?old:Dynamic) {
    var isOld = getStatics(old).exists;

    for (f in getStatics(c).keys())
      if (isOld(f))
        Reflect.setField(c, f, Reflect.field(old, f));
  }

  static function bootProto(c:Dynamic, ?old:Dynamic) {
    var proto:Dict<Dynamic> = c.prototype,
        closures = meta(haxe.rtti.Meta.getFields(c), 'hotreload.closure');

    function forward(name)
      return function () {
        return proto[name].apply(__js('this'), __js('arguments'));
      }

    for (k in closures.keys()) {
      var alias = 'hotreload.$k';
      proto[alias] = proto[k];
      proto[k] = forward(alias);
    }

    if (old != null) {
      var oldProto:Dict<Dynamic> = old.prototype;
      for (k => v in oldProto)
        if (Reflect.isFunction(v))
          switch proto[k] {
            case null:
            case Reflect.isFunction(_) => true:
              oldProto[k] = forward(k);
            default:
          }
        else {
          // TODO: should anything happen here?
        }
    }
  }

  static function getClasses(node:Node) {
    var ret = new Dict<Dynamic>();

    node.crawl(c -> switch Type.getClassName(c) {
      case null:
      case name: ret[name] = c;
    });

    return ret;
  }

  static function doPatch(oldRoot:Node) {

    var oldClasses = getClasses(oldRoot),
        newClasses = getClasses(getRoot());

    for (k => v in oldClasses)
      if (v.onHotswapUnload)
        v.onHotswapUnload(newClasses.exists(k));

    for (n => c in newClasses) {
      bootProto(c, oldClasses[n]);
      updateStatics(c, oldClasses[n]);
    }

    for (n => c in newClasses)
      bootClass(c, oldClasses[n]);
  }
}

private abstract Node(Dynamic) from Package {

  public var kind(get, never):NodeKind;
    function get_kind()
      return
        if (isClass) Cls(this);
        else Pack(this);

  public var isClass(get, never):Bool;
    inline function get_isClass()
      return !!this.__name__;

  public function keyValueIterator():KeyValueIterator<String, Node>
    return if (this.__name__ || this.__ename__) EMPTY else (this:Package).keyValueIterator();

  public function crawl(handleClass:Dynamic->Void)
    for (name => node in keyValueIterator())
      if (node.isClass) handleClass(node)
      else node.crawl(handleClass);

  static final EMPTY = [].iterator();
}

private enum NodeKind {
  Cls(c:Dynamic);
  Pack(p:Package);
}

private typedef Package = Dict<Node>;