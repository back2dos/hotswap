# hotswap

Code hotswapping for Haxe generated JavaScript.

## Disclaimer

Hot swapping code is a complicated matter. It is fair to say that in general, it is strictly impossible. It can only be made to work in specific cases. So even when this library has made it past its experimental stages, it will impose quite significant restrictions to the code it's supposed to work with.

It will also *always* have performance implications.

## Inner workings

### `hx` Namespace

When compiled with `hotswap` all classes compiled with `-D js-unflatten` and their names changed to `hx.the$full$dotpath$ClassName`.

This means that all classes wind up in a variable called `hx`, roughly like so:

```js
var hx = {};
hx.Reflect = function() { };
hx.haxe$rtti$Meta = function() { };
```

The code swapping is primarily accomplished by assigning the value of `hx` from the new code to the `hx` variable present in the old code.

This has implications for some reflection APIs like `Type.resolveClass` and `Type.getClassName`. Their implementations are rewired to hide this difference. You may still notice it when looking at the generated JavaScript.

### Initialization

When your code executes for the first time, `hotswap` does a few things:

1. **Closure wrapping**: For any method closures discovered at compile time, the method is wrapped into an alias, roughly like so:

   ```js
   var alias = 'hotswap.' + originalName;
   theClass.prototype[alias] = theClass.prototype[originalName];
   theClass.prototype[originalName] = function () { return this[alias].apply(this, arguments) };
   ```

   This is made so that `$bind` as used by Haxe to ensure method closures don't lose `this` doesn't copy the implementation in an unreversible manner.

2. **Prototype Indirection**: Prepend an empty `{}` into the prototype chain of every class. This is so that during reloading `Object.setPrototypeOf(oldClass.prototype, newClass.prototype)` will affect all existing instances of oldClass.

3. further static initialization (as genereated by Haxe).

4. **`onHotswapLoad` Callbacks**: Any class that defines `static function onHotswapLoad(firstTime:Bool)` will have it invoked with a flag indicating whether the class is loaded for the first time (so during initialization it is always `true`).
5. `main` entry point is called.

### Reload

New code is loaded via `hotswap.Runtime.patch`, which does a whole number of things. Note that the `main` entry point of the new code is *not* called.

1. the code is `eval`ed (unless it's the same as the last value passed to `hotswap.Runtime.patch`), in a context where a `var hxPatch = null` is available and assigns the value of its `hx` "namespace" is assigned to `hxPatch`.

2. by virtue of being loaded, the loaded code will perform closure wrapping, prototype indirection and its own static initialization

3. any old class that defines `static function onHotswapUnload(stillExists:Bool)` will have it invoked with with a flag indicating if the class exists in the new code as well.

4. the outer code keeps a reference to the previous value of `hx` and assigns the value stored in `hxPatch` to it. From this point forward, all code points to the new classes.

5. the empty prototypes of the old classes are pointed to the protypes of the new classes.

6. any writable `static var` or `static dynamic function` in the new classes is assigned the value from the corresponding old class. The basic assumption here is that these values are meant to change at runtime and therefore the current runtime value trumps the initial value from the new code.

7. `onHotswapLoad` callbacks are executed, but the `firstTime` flag is now false for every class that existed in the previous code as well.

8. `hotswap.Runtime` defines a `static public var onReload(get, never):Signal<{ final revision:Int; }>` that fires accordingly.

## Some of the things that will not work

Many things will simply not work as might be expected, or at least desired, but let's list a few.

#### Keeping references to class objects

Upon reload, they will point to the old classes. Meaning that even `Std.is(someFoo, staleReferenceToFoo)` will yield false. Be inventive. Instead of passing around class references, pass around predicates, e.g.:

```haxe
// Don't
  var type:Class<Dynamic> = Foo;
  // and later
  if (Std.is(candidate, type)) {
    trace('oh yeah!')
  }
// Do
  var typeChecker:Dynamic->Bool = v -> Std.is(v, Foo);
  // and later
  if (typeChecker(candidate))) {
    trace('oh yeah!')
  }
```

The second approach is also more flexible, because in essence it uses filter functions and those are composeable.

#### Having code in persisted anonymous functions

Upon reload, such code will not change, e.g.

```haxe
document.addEventListener('click', function () {
  trace('clicked');
});
```

If you change that anonymous function above and the code is reloaded, the change is not reflected (unless of course the `document.addEventListener` section is reexecuted ... in that case make sure to cleanup event listeners in `onHotswapUnload`)

#### Removing classes or methods that are otherwise persisted

Let's consider this example:

```haxe
class Foo {
  static function onHotswapLoad(firstTime:Bool)
    if (firstTime)
      document.addEventListener('click', function () {
        rejoice();
      });

  static function rejoice()
    trace('oh yeah, I just got clicked!!!!');
}
```

After the class is unloaded, the next click will lead to an attempt to call `hx.Foo.rejoice()` and that'll throw `Cannot read property 'rejoice' of undefined`.

#### Adding new fields that are initialized via constructor

```haxe
class Foo {
  public function new() {
    document.addEventListener('click', handleClick);
  }
  function handleClick() {
    trace('click');
  }
}
```

Now let's suppose we changed it like so:

```haxe
class Foo {
  var clicks = [];
  public function new() {
    document.addEventListener('click', handleClick);
  }
  function handleClick(event) {
    trace('click number ${clicks.push(even)}');
  }
}
```

On the next click, this will fail, because `clicks` never gets initialized (haxe in fact moves the initialization to the constructor, but the constructor is not executed on existing classes).

The way to avoid this, is to make the initialization of `clicks` lazy:

```haxe
class Foo {
  var clicks(get, null);
  function get_clicks()
    return if (clicks == null) clicks = [] else clicks;
```

There's potential for solving this implicitly via macros.

#### Static Initialization

Be very careful around it. Avoid `__init__` like the plague too. Both are a great way to shoot yourself in the foot, because they may just not quite work as expected during reload. When in doubt:

- use lazy initialization
- move it into `onHotswapLoad`, as that gives you more context and therefore more control.