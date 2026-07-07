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

    <main v-loading="loading" class="user-center__panel">
      <el-tabs v-model="activeTab">
        <el-tab-pane label="用户动态" name="events">
          <header class="user-center__panel-header">
            <h2>用户动态</h2>
            <el-button @click="loadData">刷新</el-button>
          </header>
          <el-timeline v-if="events.length > 0">
            <el-timeline-item v-for="event in events" :key="event.id" :timestamp="event.createTime" placement="top">
              <p>{{ event.content }}</p>
            </el-timeline-item>
          </el-timeline>
          <el-empty v-else description="暂无动态" />
        </el-tab-pane>

        <el-tab-pane label="个人资料" name="profile">
          <el-form ref="formRef" class="user-center__form" :model="form" :rules="rules" label-width="96px">
            <el-form-item label="真实姓名" prop="realName">
              <el-input v-model="form.realName" />
            </el-form-item>
            <el-form-item label="年龄">
              <el-input v-model="form.age" />
            </el-form-item>
            <el-form-item label="性别">
              <el-select v-model="form.sex" clearable placeholder="请选择">
                <el-option label="男" :value="1" />
                <el-option label="女" :value="2" />
              </el-select>
            </el-form-item>
            <el-form-item label="出生日期">
              <el-date-picker v-model="form.birthDay" value-format="YYYY-MM-DD" type="date" placeholder="选择日期" />
            </el-form-item>
            <el-form-item label="手机">
              <el-input v-model="form.phone" />
            </el-form-item>
            <el-form-item>
              <el-button type="primary" :loading="saving" @click="saveProfile">保存资料</el-button>
            </el-form-item>
          </el-form>
        </el-tab-pane>
      </el-tabs>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import {
  getCurrentStudentUser,
  getStudentUserEvents,
  updateCurrentStudentUser,
  type StudentUserInfo,
  type UserEventLog
} from '@xzs/api-client'

const loading = ref(false)
const saving = ref(false)
const activeTab = ref('events')
const user = ref<StudentUserInfo | null>(null)
const events = ref<UserEventLog[]>([])
const formRef = ref<FormInstance>()
const form = ref({
  realName: '',
  age: '',
  sex: undefined as number | undefined,
  birthDay: null as string | null,
  phone: '',
  userLevel: 1
})
const rules: FormRules = {
  realName: [{ required: true, message: '请输入真实姓名', trigger: 'blur' }]
}
const userInitial = computed(() => user.value?.userName?.slice(0, 1).toUpperCase() ?? 'U')

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const [userResult, eventResult] = await Promise.all([getCurrentStudentUser(), getStudentUserEvents()])
    user.value = userResult.response ?? null
    syncForm(user.value)
    events.value = eventResult.response ?? []
  } finally {
    loading.value = false
  }
}

async function saveProfile() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) {
    return
  }

  saving.value = true
  try {
    const result = await updateCurrentStudentUser({
      realName: form.value.realName,
      age: form.value.age,
      sex: form.value.sex ?? null,
      birthDay: form.value.birthDay,
      phone: form.value.phone,
      userLevel: form.value.userLevel
    })

    if (result.code === 1) {
      ElMessage.success(result.message)
      await loadData()
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    saving.value = false
  }
}

function syncForm(nextUser: StudentUserInfo | null) {
  form.value = {
    realName: nextUser?.realName ?? '',
    age: nextUser?.age == null ? '' : String(nextUser.age),
    sex: nextUser?.sex,
    birthDay: nextUser?.birthDay ?? null,
    phone: nextUser?.phone ?? '',
    userLevel: nextUser?.userLevel ?? 1
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
.user-center__panel {
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

.user-center__panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.user-center__panel-header h2 {
  margin: 0;
  color: #111827;
  font-size: 20px;
}

.user-center__form {
  max-width: 520px;
}

@media (max-width: 840px) {
  .user-center {
    grid-template-columns: 1fr;
  }
}
</style>
