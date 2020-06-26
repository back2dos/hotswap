package ;

import hotswap.Runtime;
import js.node.Fs.*;

class RunTests {

  static function main()
    if (Runtime.FIRST_LOAD) {
      var file = js.Node.__filename;
      watch(file, (a, b) -> {
        trace('change triggered');
        try Runtime.patch(readFileSync(file).toString())
        catch (e:Dynamic) {}
      });
    }

  @:keep static function onHotSwapLoad(isNew:Bool) {
    trace('loaded ($isNew)');
  }
}