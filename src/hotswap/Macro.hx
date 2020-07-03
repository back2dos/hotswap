package hotswap;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
using tink.MacroApi;
using StringTools;

class Macro {

  static final PERSIST = 'hotreload.persist';
  static final CLOSURE = 'hotreload.closure';

  static function base<T:BaseType>(r:Ref<T>):BaseType
    return r.get();

  static function processType() {
    var ret = getBuildFields();

    for (f in ret) {
      inline function modifyBody(m)
        switch f.kind {
          case FFun(fn):
            f.access.remove(AInline);
            fn.expr = m(fn.expr);
          default: f.pos.error('function expected');
        }
      switch f.name {
        case 'getClassName'
           | 'getEnumName':
          modifyBody(e -> switch e {
            case macro return $e, macro { return $e; }:
              macro @:pos(e.pos) return $e.substr(3).split('$').join('.');
            default:
              e.reject('Function body does not look as expected by hotswap. Please raise an issue.');
          });
        case 'resolveClass'
           | 'resolveEnum':
          modifyBody(e -> macro @:pos(e.pos) { name = 'hx.' + name.split('.').join('$'); ${e}});
        default:
      }
    }
    return ret;
  }

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

      var id = macro $v{getId(t)};

      t.meta.add(':native', [id], id.pos);
    }

  static function getId(t:BaseType)
    return 'hx.' + t.pack.concat([t.name]).join('$');

  static function keep(o:{ meta:MetaAccess })
    if (!o.meta.has(':keep'))
      o.meta.add(':keep', [], (macro null).pos);

  static function use() {
    switch MacroApi.getMainClass() {
      case None: (macro null).pos.error('no entry point');
      case Some(v):
        Compiler.addGlobalMetadata(v, '@:build(hotswap.Macro.processMain())');
    }

    Compiler.addGlobalMetadata('Type', '@:build(hotswap.Macro.processType())');

    onGenerate(types -> {
      for (t in types)
        switch t {
          case TEnum(_.get() => e, _): move(e);
          case TInst(_.get() => c, _):

            move(c);
            var statics = c.statics.get();
            for (f in c.statics.get())
              switch f.kind {
                case FVar(_, AccNormal) | FMethod(MethDynamic):
                  f.meta.add(PERSIST, [], (macro null).pos);
                default:
                  if (f.name.startsWith('onHotswap')) keep(f);
              }

            for (fields in [statics, c.fields.get()])
              for (f in fields) {
                function seek(t:TypedExpr) if (t != null) {
                  t.iter(seek);
                  switch t {
                    case { expr: TField(_, FClosure(_, _.get() => cf))} if (!cf.meta.has(CLOSURE)):
                      cf.meta.add(CLOSURE, [], (macro null).pos);
                    default:
                  }
                }
                seek(f.expr());
              }

          default:
        }
    });
  }
}
#end