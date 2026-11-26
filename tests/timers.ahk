class TrackedTimerSnapshot {
    static released := 0

    __Delete() {
        TrackedTimerSnapshot.released += 1
    }
}

RunIndependentTimerTest() {
    events := []
    randomLimits := []
    randomDelay := 0
    GUIManager.RunMod := {Value: 1}
    GUIManager.uCtrl := Map(
        "dodge", Map("enable", {Value: 1}, "key", {Value: "A"}, "interval", {Value: 30}),
        "potion", Map("enable", {Value: 1}, "key", {Value: "B"}, "interval", {Value: 60}),
        "random", Map("enable", {Value: 1}, "max", {Value: 5}),
        "D4only", Map("enable", {Value: 0})
    )
    MacroController.isRunning := true
    KeyHandler.DefineProp("HandleKeyMode", {Call: (_, data) => events.Push(data.key)})
    UtilityHelper.DefineProp("RandomDelay", {Call: (_, limit) => (
        randomLimits.Push(limit), randomDelay := 1 + Mod(randomDelay, limit)
    )})

    KeyHandler.PressKeyCallback("uSkill", "dodge")
    KeyHandler.PressKeyCallback("uSkill", "potion")
    GUIManager.uCtrl["potion"]["key"].Value := "C"
    GUIManager.uCtrl["potion"]["interval"].Value := 3000
    GUIManager.uCtrl["random"]["enable"].Value := 0
    GUIManager.uCtrl["random"]["max"].Value := 10
    Sleep(500)
    KeyHandler.ClearAllTimers()

    counts := Map("A", 0, "B", 0)
    for key in events {
        Assert(counts.Has(key), "独立定时器保留按键快照")
        counts[key] += 1
    }
    Assert(counts["B"] >= 3 && counts["A"] > counts["B"], "两个周期各自反复执行，按启动时的间隔")
    Assert(randomLimits.Length == events.Length + 2, "每次注册和回调重挂都重新计算随机延迟")
    for limit in randomLimits
        Assert(limit == 5, "独立定时器保留随机上限快照")
    stoppedCount := events.Length
    Sleep(120)
    Assert(events.Length == stoppedCount, "取消后的独立定时器无新动作")

    build := KeyHandler.GetOwnPropDesc("_BuildKeyData").Call
    KeyHandler.DefineProp("_BuildKeyData", {Call: (self, category, id, config) => (
        snapshot := build(self, category, id, config),
        ObjSetBase(snapshot, TrackedTimerSnapshot.Prototype),
        snapshot
    )})
    GUIManager.uCtrl["dodge"]["interval"].Value := 1000
    loop 100 {
        KeyHandler.PressKeyCallback("uSkill", "dodge")
        KeyHandler.ClearAllTimers()
    }
    Assert(TrackedTimerSnapshot.released == 100, "清理后回收的快照数为 " TrackedTimerSnapshot.released " / 100")
}

RunQueueClockTest() {
    queueTestTime := 0x100000000 - 50
    events := []
    realClock := KeyQueueManager.GetOwnPropDesc("_Now").Call
    KeyQueueManager.DefineProp("_Now", {Call: (_) => queueTestTime})
    KeyHandler.DefineProp("HandleKeyMode", {Call: (_, data) => events.Push(realClock(KeyQueueManager))})
    data := {uniqueKey: "test", mode: 1, id: "test", interval: 100, randomEnabled: false}

    Critical
    KeyQueueManager.StartQueue()
    KeyQueueManager.EnqueueKey(data)
    KeyQueueManager.ProcessCycle()
    Assert(events.Length == 1, "新入队按键立即到期")

    queueTestTime += 99
    KeyQueueManager.ProcessCycle()
    Assert(events.Length == 1, "过 32 位边界后在到期前 1ms 未早发")

    queueTestTime += 1
    KeyQueueManager.ProcessCycle()
    KeyQueueManager.ProcessCycle()
    Assert(events.Length == 2, "过 32 位边界后在期限点恰执行一次")
    Assert(KeyQueueManager.expectedNext[data.uniqueKey] == queueTestTime + 100, "按原周期更新下次期限")

    waitingSince := realClock(KeyQueueManager)
    queueTestTime += 100
    Critical "Off"
    Sleep(400)
    Assert(events.Length == 3, "真实队列定时器在下一周期仍能唤醒")
    Assert(events[3] - waitingSince >= 70, "下一次实际唤醒距离重挂约 100ms")

    KeyHandler.DefineProp("HandleKeyMode", {Call: (_, data) => (queueTestTime += 10, ThrowQueueTestError())})
    queueTestTime += 100
    KeyQueueManager.ProcessCycle()
    Assert(KeyQueueManager.expectedNext[data.uniqueKey] == queueTestTime + 100, "错误退避从新的 64 位时刻起算")
    KeyQueueManager.StopQueue()
}

ThrowQueueTestError() {
    throw Error("模拟队列执行失败")
}

RunIndependentTimerTest()
RunQueueClockTest()
