package hotswap;

#if macro
import haxe.macro.Context.*;
import haxe.macro.Expr;
import haxe.macro.Type;

class Macro {
  static function base<T:BaseType>(r:Ref<T>):BaseType
    return r.get();
  static function use()
    onGenerate(types -> {
      for (t in types)
        switch t {
          case TEnum(base(_) => t, _)
             | TInst(base(_) => t, _) if (!t.isExtern):

            t.meta.remove(':native');

            var id = {
              var a = ["hx"].concat(t.pack);
              if (t.isPrivate)
                a.push('$');
              a.push(t.name);
              macro $v{a.join('.')};
            }

            t.meta.add(':native', [id], id.pos);

          default:
        }
    });
}
#end