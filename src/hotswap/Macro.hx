package hotswap;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.ds.Option;
import haxe.DynamicAccess as Dict;

using haxe.macro.Tools;
using tink.MacroApi;
using StringTools;
using sys.io.File;

class Macro {

  static final PERSIST = 'hotreload.persist';
  static final CLOSURE = ':hotreload.closure';

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
          modifyBody(e -> macro @:pos(e.pos) {
            var ret:String = (function () $e)();
            return
              if (ret.substr(0, 3) == 'hx.') ret.substr(3).split('$').join('.');
              else ret;
          });
        case 'resolveClass'
           | 'resolveEnum':
          modifyBody(e -> macro @:pos(e.pos) {
            var ret = (function () $e)();
            if (ret == null) {
              name = 'hx.' + name.split('.').join('$');
              $e;
            }
            return ret;
          });
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

  static function skip(t:BaseType)
    return switch t {
      case { isExtern: true, }: true;
      case { pack: ['haxe', 'iterators'], name: 'ArrayIterator' }
         | { module: 'haxe.Exception'}: //TODO: exceptions need to be treated properly
        true;
      default: t.meta.has(':coreType');
    }

  static function move(t:BaseType)
    return
      if (!skip(t)) {
        t.meta.remove(':native');

        var id = getId(t);
        var e = macro $v{'hx.' + id};

        t.meta.add(':native', [e], e.pos);

        Some(id);
      }
      else None;

  static function getId(t:BaseType)
    return t.pack.concat([t.name]).join('$');

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
      var closures = new Dict(),
          anonClosures = new Dict(),
          interfaceClosures = new Dict(),
          classes = [];

      for (t in types)
        switch t {
          case TEnum(_.get() => e, _): move(e);
          case TInst(_.get() => c = move(_) => Some(id), _):
            if (!c.isInterface)
              classes.push(c);

            var statics = c.statics.get();
            for (f in c.statics.get())
              switch f.kind {
                case FVar(_, AccNormal) | FMethod(MethDynamic):
                  if (!f.meta.has(PERSIST))
                    f.meta.add(PERSIST, [], (macro null).pos);
                default:
                  if (f.name.startsWith('onHotswap')) keep(f);
              }

            for (fields in [statics, c.fields.get()])
              for (f in fields) {
                function seek(t:TypedExpr) if (t != null) {
                  t.iter(seek);
                  switch t {
                    case { expr: TField(_, FClosure(target, _.get() => cf))} if (!cf.meta.has(CLOSURE)):
                      cf.meta.add(CLOSURE, [], (macro null).pos);

                      switch target {
                        case null:
                          anonClosures[cf.name] = true;
                        case _.c.get() => c = getId(_) => id:
                          var m = if (c.isInterface) interfaceClosures else closures;
                          (switch m[id] {
                            case null: m[id] = [];
                            case v: v;
                          }).push(cf.name);
                      }

                    default:
                  }
                }
                seek(f.expr());
              }

          default:
        }

      for (c in classes) {
        var id = getId(c);

        function add(name) {
          var cl = switch closures[id] {
            case null: closures[id] = [];
            case v: v;
          }
          if (cl.indexOf(name) == -1)
            cl.push(name);
        }

        function interf(i:ClassType) {
          switch interfaceClosures[getId(i)] {
            case null:
            case fields:
              for (f in fields)
                add(f);
          }
          for (i in i.interfaces)
            interf(i.t.get());
        }

        for (f in c.fields.get())
          if (anonClosures[f.name])
            if (f.kind.match(FMethod(_))) add(f.name);

        for (i in c.interfaces)
          interf(i.t.get());
      }

      var out = Compiler.getOutput() + '.hotswapmeta';
      out.saveContent('var hotswapmeta = { closures: ${haxe.Json.stringify(closures)}}');
      Compiler.includeFile(out, Closure);
    });
  }

  static function process()
    return ClassBuilder.run([lazify]);

  static public function lazify(fields:ClassBuilder) {
    for (f in fields) if (!f.isStatic)
      switch f.getVar() {
        case Success({ expr: null | macro null } | { get: 'get' }):
        case Success({ type: t, expr: e, get: get, set: set }):

          switch f.metaNamed(':isVar') {
            case []:
            default: f.addMeta(':isVar');
          }

          var getter = 'get_${f.name}';

          function write() {
            var fieldAccess = storeTypedExpr(typeExpr(macro $i{f.name}));
            return macro $fieldAccess = $e;
          }

          fields.addMembers(macro class {
            function $getter():$t
              return switch $i{f.name} {
                case null: ${write.bounce()}
                case v: v;
              }
          });

          f.kind = FProp('get', set, t, macro null);// TODO: consider generating native properties instead
        default:
      }
  }
}
#end