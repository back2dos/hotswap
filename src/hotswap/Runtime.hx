package hotswap;

import haxe.ds.Option;
import haxe.DynamicAccess as Dict;
import js.Syntax.code as __js;
import js.lib.Object.*;
import js.Lib.*;

using tink.CoreApi;

class Runtime {

  static var _reloaded = new SignalTrigger();
  static var revision = 0;
  static public var reloaded(get, never):Signal<{ final revision:Int; }>;
    static function get_reloaded()
      return _reloaded;

  static var last = '';

  static public function createPatch(source:String):Outcome<{ function apply():Bool; }, Dynamic>
    try {
      var raw:Void->Root = eval('(function () {
        var hxPatch = null;
        $source;
        return hxPatch;
      })');
      return Success({
        apply: function () {
          if (source == null || source == '' || source == last) return false;
          var nu = raw(),
              old = root;
          unload(nu);
          __js('hx = {0}', nu);
          doPatch(old);
          last = source;
          _reloaded.trigger({ revision: ++revision });
          return true;
        }
      });
    }
    catch (e:Dynamic)
      return Failure(e);

  #if nodejs
  static function watchSelf() {
    var file = js.Node.__filename;
    js.node.Fs.watch(file, (_, _) -> {
      var source =
        try js.node.Fs.readFileSync(file).toString()
        catch (e:Dynamic) null;

      if (source != null)
        switch createPatch(source) {
          case Success(p): p.apply();
          case Failure(e): js.Browser.console.error(e);
        }
    });
  }

  #else
  static public function permaPoll() {
    var url = (cast js.Browser.document.currentScript:js.html.ScriptElement).src;
    function poll() {
      var url = url + '?time=${Date.now().getTime()}';
      var h = new haxe.Http(url);
      h.onError = function (e) {
        js.Browser.console.error('Failed to load $url', e);
        haxe.Timer.delay(poll, 250);
      }
      h.onData = function (s) {
        switch createPatch(s) {
          case Failure(e): js.Browser.console.error(e);
          case Success(p): p.apply();
        }
        haxe.Timer.delay(poll, 250);
      }
      h.request();
    }
    poll();
  }
  #end

  static public final FIRST_LOAD = {
    var isFirst:Bool = __js('typeof hxPatch === "undefined"');
    if (!isFirst)
      __js('hxPatch = hx');
    else {
      #if nodejs
        watchSelf();
      #end
    }

    isFirst;
  }

  static function __init__() {
    wrapClosures();
    prototypeIndirection();
  }

  static function wrapClosures() {
    var meta:Dict<Array<String>> = untyped hotswapmeta.closures;
    for (n => closures in meta) switch root[n] {
      case null:
      case c:
        var proto = c.prototype;
        for (k in closures) {
          var alias = 'hotreload.$k';
          proto[alias] = proto[k];
          proto[k] = proto.forward(alias);
        }
    }
  }

  static function prototypeIndirection() {
    for (n => c in root) {
      var wrapper = new Proto();
      switch c.prototype {
        case null:
        case v:
          setPrototypeOf(cast wrapper, cast v);
      }
      c.prototype = wrapper;
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
    return
      if (c == null) null;
      else {
        var meta = haxe.rtti.Meta.getStatics(c),
            ret = new Dict<Bool>();

        for (f in Reflect.fields(meta))
          ret[f] = Reflect.hasField(Reflect.field(meta, f), 'hotreload.persist');

        ret;
      }

  static function updateStatics(c:Cls, ?old:Cls)
    if (old != null) {
      var isOld = getStatics(old).exists;

      for (f in getStatics(c).keys())
        if (isOld(f) && Reflect.hasField(old, f)) // the old field may have been eliminated
          Reflect.setField(c, f, Reflect.field(old, f));
    }

  static function rewireProto(c:Cls, ?old:Cls)
    if (old != null) {
      var protos = [old.prototype];
      switch old.hotreloadProtoHistory {
        case null:
        case v: protos = protos.concat(v);
      }
      c.hotreloadProtoHistory = protos;

      var proto = c.prototype;
      for (oldProto in protos)
        setPrototypeOf(cast oldProto, getPrototypeOf(cast proto));
    }

  static function unload(newRoot:Root)
    for (k => v in root)
      if (v.onHotswapUnload)
        v.onHotswapUnload(newRoot.exists(k));

  static function doPatch(oldRoot:Root) {

    for (n => c in root) {
      rewireProto(c, oldRoot[n]);
      updateStatics(c, oldRoot[n]);
    }

    for (n => c in root)
      bootClass(c, oldRoot[n]);
  }
}

private typedef Root = Dict<Cls>;

@:forward
private abstract Cls(Dynamic) {
  public var prototype(get, set):Proto;
    inline function get_prototype():Proto
      return this.prototype;

    inline function set_prototype(proto:Proto):Proto
      return this.prototype = proto;
}

@:forward
private abstract Proto(Dict<Dynamic>) {
  public inline function new()
    this = new Dict();

  public function forward(name)
    return function () {
      return (nativeThis:Dict<Dynamic>)[name].apply(nativeThis, __js('arguments'));
    }

  @:op([]) public inline function get(name)
    return this.get(name);

  @:op([]) public inline function set(name, value)
    return this.set(name, value);

}