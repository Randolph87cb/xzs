<template>
  <section class="dashboard">
    <div>
      <p class="dashboard__eyebrow">学习概览</p>
      <h1>今日考试</h1>
    </div>
    <div class="dashboard__stats" aria-label="考试概览">
      <div class="dashboard__stat">
        <span>待完成</span>
        <strong>0</strong>
      </div>
      <div class="dashboard__stat">
        <span>已完成</span>
        <strong>0</strong>
      </div>
      <div class="dashboard__stat">
        <span>消息</span>
        <strong>0</strong>
      </div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.dashboard {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 24px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.dashboard__eyebrow {
  margin: 0 0 6px;
  color: #64748b;
  font-size: 14px;
}

.dashboard h1 {
  margin: 0;
  font-size: 22px;
  color: #111827;
}

.dashboard__stats {
  display: grid;
  grid-template-columns: repeat(3, minmax(80px, 1fr));
  gap: 12px;
}

.dashboard__stat {
  display: grid;
  gap: 4px;
  min-width: 80px;
  padding: 12px;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  background: #f8fafc;
}

.dashboard__stat span {
  color: #64748b;
  font-size: 13px;
}

.dashboard__stat strong {
  color: #0f172a;
  font-size: 22px;
}

@media (max-width: 640px) {
  .dashboard {
    align-items: stretch;
    flex-direction: column;
  }

  .dashboard__stats {
    grid-template-columns: repeat(3, 1fr);
  }
}
</style>
