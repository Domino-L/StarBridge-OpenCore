/// Motion presets offered on the overlay settings page: each sets these
/// workspace setting fields together. Unknown names change nothing.
const overlayExperiencePresets = <String, Map<String, Object>>{
  'Smooth': {
    'enableStartupTransition': true,
    'startupTransitionFrameRate': 'Fps120',
    'animationFrameRate': 'Fps120',
  },
  'ReducedMotion': {
    'enableStartupTransition': false,
    'startupTransitionFrameRate': 'Fps60',
    'animationFrameRate': 'Fps60',
  },
  'Balanced': {
    'enableStartupTransition': true,
    'startupTransitionFrameRate': 'Fps60',
    'animationFrameRate': 'Fps60',
  },
};
