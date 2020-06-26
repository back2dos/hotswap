package hotswap;

import haxe.ds.Option;
import js.Syntax.code as __js;

class Runtime {
  static var last = '';
  static public function patch(source:String) {
    if (source == null || source == '' || source == last) return;
    __js('var hxPatch = {0}', Runtime);
    trace([source.length, last.length]);
    js.Lib.eval(source);
    next.doPatch(__js('hx'));
    last = source;
  }
  static var next = Runtime;
  static public final FIRST_LOAD = {
    var isFirst = __js('typeof hxPatch === "undefined"');
    if (!isFirst)
      __js('hxPatch.next = {0}', Runtime);
    isFirst;
  }

  static function boot() {

  }

  static function getClasses(node:Node) {
    var ret = new haxe.DynamicAccess<Dynamic>();

    node.crawl(c -> switch Type.getClassName(c) {
      case null:
      case name: ret[name] = c;
    });

    return ret;
  }
  static function doPatch(oldRoot:Package) {
    var newRoot:Package = untyped hx;

    var oldClasses = getClasses(oldRoot),
        newClasses = getClasses(newRoot);

    for (k => v in oldClasses)
      if (v.onHotSwapUnload)
        v.onHotSwapUnload(newClasses.exists(k));

    for (k => v in newRoot)
      oldRoot[k] = v;

    for (old in [for (k => v in oldRoot) if (!newRoot.exists(k)) k])
      oldRoot.remove(old);

    for (k => v in newClasses)
      if (v.onHotSwapLoad)
        v.onHotSwapLoad(oldClasses.exists(k));

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