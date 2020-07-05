package ;

import hotswap.Runtime;
import js.node.Fs.*;

class RunTests {
  static var counter = 0;
  static var r = new foo.Inst().method;
  static function main() {
    trace('hello!!!');
  }

  static function onHotswapLoad(isNew:Bool) {
    trace('loaded ($isNew) - ${++counter}!');
    r();
  }
}