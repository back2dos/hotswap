package ;

import hotswap.Runtime;
import js.node.Fs.*;

class RunTests {
  static var counter = 0;
  static var r = new foo.Inst().method;
  static function main() {
    var file = js.Node.__filename;
    watch(file, (a, b) -> {
      trace('change #${counter++} triggered');

      try Runtime.patch(readFileSync(file).toString())
      catch (e:Dynamic) {}
    });
  }

  static function onHotswapLoad(isNew:Bool) {
    trace('loaded ($isNew) - $counter!');
    r();
  }
}