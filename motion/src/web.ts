import { WebPlugin } from '@capacitor/core';

import type { AccelListenerEvent, MotionPlugin, OrientationListenerEvent } from './definitions';

export class MotionWeb
  extends WebPlugin<{ accel: AccelListenerEvent; orientation: OrientationListenerEvent }>
  implements MotionPlugin
{
  constructor() {
    super();
    this.registerWindowListener('devicemotion', 'accel');
    this.registerWindowListener('deviceorientation', 'orientation');
  }
}
