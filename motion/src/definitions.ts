import type { PluginListenerHandle } from '@capacitor/core';

export interface MotionPlugin {
  /**
   * Add a listener for accelerometer data
   *
   * @since 1.0.0
   */
  addListener(eventName: 'accel', listenerFunc: AccelListener): Promise<PluginListenerHandle>;

  /**
   * Add a listener for device orientation change (compass heading, etc.)
   *
   * @since 1.0.0
   */
  addListener(eventName: 'orientation', listenerFunc: OrientationListener): Promise<PluginListenerHandle>;

  /**
   * Remove all the listeners that are attached to this plugin.
   *
   * @since 1.0.0
   */
  removeAllListeners(): Promise<void>;
}

export type AccelListener = (event: AccelListenerEvent) => void;
export type OrientationListener = (event: OrientationListenerEvent) => void;
export type OrientationListenerEvent = RotationRate;

export interface RotationRate {
  /**
   * The amount of rotation around the Z axis, in degrees per second. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  alpha: number | null;

  /**
   * The amount of rotation around the X axis, in degrees per second. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  beta: number | null;

  /**
   * The amount of rotation around the Y axis, in degrees per second. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  gamma: number | null;
}

export interface Acceleration {
  /**
   * The amount of acceleration along the X axis. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  x: number | null;

  /**
   * The amount of acceleration along the Y axis. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  y: number | null;

  /**
   * The amount of acceleration along the Z axis. `null` when the device cannot provide it.
   *
   * @since 1.0.0
   */
  z: number | null;
}

export interface AccelListenerEvent {
  /**
   * An object giving the acceleration of the device on the three axis X, Y and Z. Acceleration is expressed in m/s. `null` when the device has no accelerometer.
   *
   * @since 1.0.0
   */
  acceleration: Acceleration | null;

  /**
   * An object giving the acceleration of the device on the three axis X, Y and Z with the effect of gravity. Acceleration is expressed in m/s. `null` when the device has no accelerometer.
   *
   * @since 1.0.0
   */
  accelerationIncludingGravity: Acceleration | null;

  /**
   * An object giving the rate of change of the device's orientation on the three orientation axis alpha, beta and gamma. Rotation rate is expressed in degrees per seconds. `null` when the device has no gyroscope.
   *
   * @since 1.0.0
   */
  rotationRate: RotationRate | null;

  /**
   * A number representing the interval of time, in milliseconds, at which data is obtained from the device.
   *
   * @since 1.0.0
   */
  interval: number;
}
