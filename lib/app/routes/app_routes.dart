abstract class Routes {
  static const splash = '/';
  static const auth = '/auth';
  static const profileSetup = '/profile-setup';
  static const profile = '/profile';
  static const home = '/home';
  static const createRoom = '/create-room';
  static const join = '/join';
  static const notifications = '/notifications';

  static const roomPattern = '/room/:roomId';
  static const roomSettingsPattern = '/room/:roomId/settings';
  static const recurringPattern = '/room/:roomId/recurring';
  static const activityPattern = '/room/:roomId/activity';
  static const splitNewPattern = '/room/:roomId/new-split';
  static const splitPattern = '/room/:roomId/split/:splitId';
  static const splitEditPattern = '/room/:roomId/split/:splitId/edit';
  static const settlePattern = '/room/:roomId/settle';
  static const statsPattern = '/room/:roomId/stats';

  static String room(String roomId) => '/room/$roomId';
  static String roomSettings(String roomId) => '/room/$roomId/settings';
  static String recurring(String roomId) => '/room/$roomId/recurring';
  static String activity(String roomId) => '/room/$roomId/activity';
  static String splitNew(String roomId) => '/room/$roomId/new-split';
  static String split(String roomId, String splitId) => '/room/$roomId/split/$splitId';
  static String splitEdit(String roomId, String splitId) => '/room/$roomId/split/$splitId/edit';
  static String settle(String roomId) => '/room/$roomId/settle';
  static String stats(String roomId) => '/room/$roomId/stats';
}
