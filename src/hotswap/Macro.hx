package hotswap;

import haxe.macro.Compiler;
#if macro
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;

using tink.MacroApi;
using StringTools;

class Macro {

  static function base<T:BaseType>(r:Ref<T>):BaseType
    return r.get();

  static function processMain() {
    var ret = getBuildFields();
    for (f in ret)
      if (f.name == 'main')
        switch f.kind {
          case FFun(f):
            f.expr = macro
              if (hotswap.Runtime.FIRST_LOAD) {
                @:privateAccess hotswap.Runtime.boot();
                ${f.expr};
              }
              else {}
          default: throw 'assert';
        }
    return ret;
  }

  static function move(t:BaseType)
    if (!t.isExtern) {
      t.meta.remove(':native');

      var id = {
        var a = ["hx"].concat(t.pack);
        if (t.isPrivate)
          a.push('$');
        a.push(t.name);
        macro $v{a.join('.')};
      }

      t.meta.add(':native', [id], id.pos);
    }

  static function keep(o:{ meta:MetaAccess })
    if (!o.meta.has(':keep'))
      o.meta.add(':keep', [], (macro null).pos);

  static function use() {
    switch MacroApi.getMainClass() {
      case None: (macro null).pos.error('no entry point');
      case Some(v): Compiler.addGlobalMetadata(v, '@:build(hotswap.Macro.processMain())');
    }
    onGenerate(types -> {
      for (t in types)
        switch t {
          case TEnum(_.get() => e, _): move(e);
          case TInst(_.get() => c, _): move(c);
            for (f in c.statics.get())
              switch f.kind {
                case FVar(_, AccNormal):
                  f.meta.add('hotreload.persist', [], (macro null).pos);
                default:
                  if (f.name.startsWith('onHotswap')) keep(f);
              }

          default:
        }
    });
  }
}
#end