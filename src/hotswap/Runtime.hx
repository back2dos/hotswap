package hotswap;

import haxe.ds.Option;
import js.Syntax.code as __js;

class Runtime {
  static var last = '';
  static public function patch(source:String) {
    if (source == null || source == '' || source == last) return;
    var old = __js('hx'),
        statics = statics;
    __js('var hxPatch = null');
    js.Lib.eval(source);
    doPatch(old, statics);
    last = source;
  }
  static public final FIRST_LOAD = {
    var isFirst:Bool = __js('typeof hxPatch === "undefined"');
    trace('load: $isFirst');
    if (!isFirst)
      __js('hxPatch = hx');
    isFirst;
  }

  static function boot() {
    final root:Node = __js('hx');
    root.crawl(bootClass);
    root.crawl(c -> if (c.onHotswapLoad != null) c.onHotswapLoad(true));
  }

  static var statics = new Statics();

  static function bootClass(c:Dynamic) {
    var initial:haxe.DynamicAccess<Dynamic> = Reflect.copy(c);
    initial.remove('prototype');
    statics[Type.getClassName(c)] = initial;
  }

  static function getClasses(node:Node) {
    var ret = new haxe.DynamicAccess<Dynamic>();

    node.crawl(c -> switch Type.getClassName(c) {
      case null:
      case name: ret[name] = c;
    });

    return ret;
  }
  static function doPatch(oldRoot:Package, statics:Statics) {
    var newRoot:Package = __js('hx');

    var oldClasses = getClasses(oldRoot),
        newClasses = getClasses(newRoot);

    for (k => v in oldClasses)
      if (v.onHotswapUnload)
        v.onHotswapUnload(newClasses.exists(k));

    for (k => v in newRoot)
      oldRoot[k] = v;

    for (old in [for (k => v in oldRoot) if (!newRoot.exists(k)) k])
      oldRoot.remove(old);

    for (k => v in newClasses) {
      switch oldClasses[k] {
        case null: trace('is new: $k');
        case old:
          for (f => initial in statics[k])
            switch Reflect.field(old, f) {
              case _ == initial => true:
              case changed:
                trace('changed: $k.$f');
                Reflect.setField(v, f, changed);
            }
      }
      bootClass(v);
    }


    for (k => v in newClasses)
      if (v.onHotswapLoad)
        v.onHotswapLoad(!oldClasses.exists(k));

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

private typedef Package = haxe.DynamicAccess<Node>;

private typedef Statics = haxe.DynamicAccess<haxe.DynamicAccess<Dynamic>>;