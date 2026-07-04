<template>
  <section class="user-center">
    <aside class="user-center__profile">
      <el-avatar :size="96" :src="user?.imagePath">{{ userInitial }}</el-avatar>
      <h1>{{ user?.userName }}</h1>
      <p>{{ user?.realName }}</p>
      <dl>
        <div><dt>注册时间</dt><dd>{{ user?.createTime ?? '-' }}</dd></div>
        <div><dt>年龄</dt><dd>{{ user?.age ?? '-' }}</dd></div>
        <div><dt>性别</dt><dd>{{ sexText(user?.sex) }}</dd></div>
        <div><dt>手机</dt><dd>{{ user?.phone ?? '-' }}</dd></div>
      </dl>
    </aside>

    <main v-loading="loading" class="user-center__events">
      <header>
        <h2>用户动态</h2>
        <el-button @click="loadData">刷新</el-button>
      </header>
      <el-timeline v-if="events.length > 0">
        <el-timeline-item v-for="event in events" :key="event.id" :timestamp="event.createTime" placement="top">
          <p>{{ event.content }}</p>
        </el-timeline-item>
      </el-timeline>
      <el-empty v-else description="暂无动态" />
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { getCurrentStudentUser, getStudentUserEvents, type StudentUserInfo, type UserEventLog } from '@xzs/api-client'

const loading = ref(false)
const user = ref<StudentUserInfo | null>(null)
const events = ref<UserEventLog[]>([])
const userInitial = computed(() => user.value?.userName?.slice(0, 1).toUpperCase() ?? 'U')

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const [userResult, eventResult] = await Promise.all([getCurrentStudentUser(), getStudentUserEvents()])
    user.value = userResult.response ?? null
    events.value = eventResult.response ?? []
  } finally {
    loading.value = false
  }
}

function sexText(sex?: number) {
  if (sex === 1) {
    return '男'
  }

  if (sex === 2) {
    return '女'
  }

  return '-'
}
</script>

<style scoped lang="scss">
.user-center {
  display: grid;
  grid-template-columns: 280px minmax(0, 1fr);
  gap: 18px;
}

.user-center__profile,
.user-center__events {
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.user-center__profile {
  display: grid;
  justify-items: center;
  align-content: start;
  gap: 12px;
}

.user-center__profile h1,
.user-center__profile p {
  margin: 0;
}

.user-center__profile dl {
  display: grid;
  gap: 10px;
  width: 100%;
  margin: 12px 0 0;
}

.user-center__profile div {
  display: grid;
  gap: 4px;
}

.user-center__profile dt {
  color: #64748b;
  font-size: 13px;
}

.user-center__profile dd {
  margin: 0;
  color: #111827;
}

.user-center__events header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.user-center__events h2 {
  margin: 0;
  color: #111827;
  font-size: 20px;
}

@media (max-width: 840px) {
  .user-center {
    grid-template-columns: 1fr;
  }
}
</style>
