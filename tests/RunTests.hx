package ;

import hotswap.Runtime;
import js.node.Fs.*;

class RunTests {
  static var counter = 0;
  static function main()
    if (Runtime.FIRST_LOAD) {
      var file = js.Node.__filename;
      watch(file, (a, b) -> {
        trace('change #${counter++} triggered');

        try Runtime.patch(readFileSync(file).toString())
        catch (e:Dynamic) {}
      });
    }

  static function onHotswapLoad(isNew:Bool) {
    trace('loaded ($isNew) - $counter!');
  }
}