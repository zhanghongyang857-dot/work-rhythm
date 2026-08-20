import Foundation
import TimerCore

let start = Date(timeIntervalSince1970: 0)

var paused = TimerEngine()
paused.start(at: start)
paused.pause(at: start.addingTimeInterval(120))
precondition(paused.cumulativeFocus(at: start.addingTimeInterval(420)) == 120)

var resumed = TimerEngine()
resumed.start(at: start)
resumed.pause(at: start.addingTimeInterval(120))
resumed.resume(at: start.addingTimeInterval(420))
resumed.stop(at: start.addingTimeInterval(600))
precondition(resumed.cumulativeFocus(at: start.addingTimeInterval(600)) == 300)

var sleeping = TimerEngine()
sleeping.start(at: start)
sleeping.handleSleep(at: start.addingTimeInterval(60))
precondition(sleeping.status == .paused)
precondition(sleeping.cumulativeFocus(at: start.addingTimeInterval(600)) == 60)

var breakDue = TimerEngine()
breakDue.start(at: start)
breakDue.resolveBreakDue(at: start.addingTimeInterval(50 * 60))
precondition(breakDue.status == .breakDue)
precondition(breakDue.cumulativeFocus(at: start.addingTimeInterval(55 * 60)) == 50 * 60)
precondition(breakDue.remainingBreakSeconds(at: start.addingTimeInterval(55 * 60)) == 0)
breakDue.beginBreak(at: start.addingTimeInterval(55 * 60))
precondition(breakDue.status == .resting)
precondition(breakDue.cumulativeFocus(at: start.addingTimeInterval(55 * 60)) == 50 * 60)
precondition(breakDue.remainingRestSeconds(at: start.addingTimeInterval(58 * 60)) == 2 * 60)
breakDue.resolveRestCompletion(at: start.addingTimeInterval(60 * 60))
precondition(breakDue.status == .idle)
precondition(breakDue.remainingBreakSeconds(at: start.addingTimeInterval(60 * 60)) == 50 * 60)

var deferred = TimerEngine()
deferred.start(at: start)
deferred.resolveBreakDue(at: start.addingTimeInterval(50 * 60))
deferred.deferBreak(at: start.addingTimeInterval(55 * 60))
precondition(deferred.status == .running)
precondition(deferred.activeFocus(at: start.addingTimeInterval(60 * 60)) == 55 * 60)
precondition(deferred.remainingBreakSeconds(at: start.addingTimeInterval(60 * 60)) == 5 * 60)

let encoded = try JSONEncoder().encode(resumed)
let decoded = try JSONDecoder().decode(TimerEngine.self, from: encoded)
precondition(decoded.status == .idle)
precondition(decoded.cumulativeFocus(at: start.addingTimeInterval(600)) == 300)

print("TimerCoreCheck: 7 checks passed")
