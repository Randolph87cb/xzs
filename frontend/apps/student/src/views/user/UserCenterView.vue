<template>
  <section class="user-center" v-loading="loading">
    <aside class="user-center__profile">
      <el-avatar :size="96" :src="user?.imagePath">{{ userInitial }}</el-avatar>
      <h1>{{ displayName }}</h1>
      <p>{{ user?.userName ?? '-' }}</p>
    </aside>

    <main class="user-center__panel">
      <header class="user-center__panel-header">
        <div>
          <p>修改个人信息</p>
          <h2>个人资料</h2>
        </div>
      </header>

      <el-descriptions :column="2" border class="user-center__descriptions">
        <el-descriptions-item label="用户名">{{ user?.userName ?? '-' }}</el-descriptions-item>
        <el-descriptions-item label="真实姓名">{{ user?.realName ?? '-' }}</el-descriptions-item>
        <el-descriptions-item label="班级">{{ classText }}</el-descriptions-item>
        <el-descriptions-item label="注册时间">{{ user?.createTime ?? '-' }}</el-descriptions-item>
      </el-descriptions>

      <el-form ref="formRef" class="user-center__form" :model="form" :rules="rules" label-width="84px">
        <el-form-item label="昵称" prop="nickName">
          <el-input v-model="form.nickName" maxlength="255" placeholder="请输入昵称" show-word-limit />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="saving" @click="saveProfile">保存</el-button>
        </el-form-item>
      </el-form>

      <section class="user-center__password">
        <header class="user-center__panel-header">
          <div>
            <p>账号安全</p>
            <h2>修改密码</h2>
          </div>
        </header>

        <el-form
          ref="passwordFormRef"
          class="user-center__form"
          :model="passwordForm"
          :rules="passwordRules"
          label-width="84px"
        >
          <el-form-item label="旧密码" prop="oldPassword">
            <el-input v-model="passwordForm.oldPassword" type="password" show-password autocomplete="current-password" />
          </el-form-item>
          <el-form-item label="新密码" prop="newPassword">
            <el-input v-model="passwordForm.newPassword" type="password" show-password autocomplete="new-password" />
          </el-form-item>
          <el-form-item label="确认密码" prop="confirmPassword">
            <el-input v-model="passwordForm.confirmPassword" type="password" show-password autocomplete="new-password" />
          </el-form-item>
          <el-form-item>
            <el-button type="primary" :loading="passwordSaving" @click="savePassword">修改密码</el-button>
          </el-form-item>
        </el-form>
      </section>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import {
  changeStudentPassword,
  getCurrentStudentUser,
  updateCurrentStudentUser,
  type StudentUserInfo
} from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()
const loading = ref(false)
const saving = ref(false)
const passwordSaving = ref(false)
const user = ref<StudentUserInfo | null>(userStore.userInfo)
const formRef = ref<FormInstance>()
const passwordFormRef = ref<FormInstance>()
const form = reactive({
  nickName: ''
})
const passwordForm = reactive({
  oldPassword: '',
  newPassword: '',
  confirmPassword: ''
})
const rules: FormRules = {
  nickName: [{ max: 255, message: '昵称不能超过 255 个字符', trigger: 'blur' }]
}
const passwordRules: FormRules = {
  oldPassword: [{ required: true, message: '请输入旧密码', trigger: 'blur' }],
  newPassword: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, max: 64, message: '新密码长度需为 6-64 位', trigger: 'blur' }
  ],
  confirmPassword: [
    { required: true, message: '请再次输入新密码', trigger: 'blur' },
    {
      validator: (_rule: unknown, value: string, callback: (error?: Error) => void) => {
        if (value !== passwordForm.newPassword) {
          callback(new Error('两次输入的新密码不一致'))
          return
        }
        callback()
      },
      trigger: 'blur'
    }
  ]
}

const displayName = computed(() => user.value?.nickName || user.value?.realName || user.value?.userName || '-')
const userInitial = computed(() => displayName.value.slice(0, 1).toUpperCase())
const classText = computed(() => user.value?.className || '-')

onMounted(loadUser)

async function loadUser() {
  loading.value = true
  try {
    const result = await getCurrentStudentUser()
    user.value = result.response ?? userStore.userInfo
    if (result.response) {
      userStore.setUserInfo(result.response)
      userStore.setUserName(result.response.userName)
      userStore.setImagePath(result.response.imagePath ?? '')
    }
    syncForm(user.value)
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
      nickName: form.nickName.trim()
    })

    if (result.code === 1) {
      ElMessage.success(result.message || '保存成功')
      await userStore.initUserInfo()
      user.value = userStore.userInfo
      syncForm(user.value)
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    saving.value = false
  }
}

async function savePassword() {
  const valid = await passwordFormRef.value?.validate().catch(() => false)
  if (!valid) {
    return
  }

  passwordSaving.value = true
  try {
    const result = await changeStudentPassword({
      oldPassword: passwordForm.oldPassword,
      newPassword: passwordForm.newPassword,
      confirmPassword: passwordForm.confirmPassword
    })
    if (result.code === 1) {
      ElMessage.success(result.message || '密码已修改')
      resetPasswordForm()
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    passwordSaving.value = false
  }
}

function syncForm(nextUser: StudentUserInfo | null) {
  form.nickName = nextUser?.nickName ?? ''
}

function resetPasswordForm() {
  passwordForm.oldPassword = ''
  passwordForm.newPassword = ''
  passwordForm.confirmPassword = ''
  passwordFormRef.value?.clearValidate()
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
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
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

.user-center__profile h1 {
  max-width: 100%;
  overflow: hidden;
  color: var(--xzs-text);
  font-size: 22px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-center__profile p {
  color: var(--xzs-text-muted);
}

.user-center__panel {
  display: grid;
  align-content: start;
  gap: 18px;
}

.user-center__panel-header p {
  margin: 0 0 6px;
  color: var(--xzs-primary);
  font-size: 14px;
  font-weight: 700;
}

.user-center__panel-header h2 {
  margin: 0;
  color: var(--xzs-text);
  font-size: 20px;
}

.user-center__descriptions {
  max-width: 720px;
}

.user-center__form {
  max-width: 520px;
}

.user-center__password {
  display: grid;
  gap: 18px;
  padding-top: 18px;
  border-top: 1px solid var(--xzs-border);
}

@media (max-width: 840px) {
  .user-center {
    grid-template-columns: 1fr;
  }
}
</style>
