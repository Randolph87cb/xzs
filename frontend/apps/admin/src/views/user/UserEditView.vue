<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>{{ roleTitle }}编辑</h1>
        <p>维护{{ roleTitle }}账号资料。</p>
      </div>
    </header>

    <el-form ref="formRef" class="user-edit-form" :model="form" :rules="rules" label-width="92px">
      <section class="user-edit__section" aria-labelledby="user-account-heading">
        <h2 id="user-account-heading">账号信息</h2>
        <el-form-item label="用户名" prop="userName">
          <el-input v-model="form.userName" />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input v-model="form.password" :placeholder="passwordPlaceholder" show-password />
        </el-form-item>
        <el-form-item label="真实姓名" prop="realName">
          <el-input v-model="form.realName" />
        </el-form-item>
        <el-form-item label="昵称">
          <el-input v-model="form.nickName" />
        </el-form-item>
      </section>

      <section v-if="role === 1" class="user-edit__section" aria-labelledby="student-profile-heading">
        <h2 id="student-profile-heading">学生资料</h2>
        <el-form-item label="年龄">
          <el-input v-model="form.age" />
        </el-form-item>
        <el-form-item label="性别">
          <el-select v-model="form.sex" clearable placeholder="性别">
            <el-option label="男" :value="1" />
            <el-option label="女" :value="2" />
          </el-select>
        </el-form-item>
        <el-form-item label="出生日期">
          <el-date-picker v-model="form.birthDay" type="date" value-format="YYYY-MM-DD" placeholder="选择日期" />
        </el-form-item>
        <el-form-item label="班级" prop="classId">
          <el-select v-model="form.classId" filterable placeholder="选择班级">
            <el-option v-for="item in classOptions" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="目标科目">
          <el-select v-model="form.targetSubjectId" clearable filterable placeholder="选择目标科目">
            <el-option v-for="item in subjectOptions" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
      </section>

      <section class="user-edit__section" aria-labelledby="user-status-heading">
        <h2 id="user-status-heading">联系与状态</h2>
        <el-form-item label="手机">
          <el-input v-model="form.phone" />
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="form.status">
            <el-option label="启用" :value="1" />
            <el-option label="禁用" :value="2" />
          </el-select>
        </el-form-item>
      </section>

      <div class="admin-sticky-actions">
        <el-button
          type="primary"
          data-testid="user-edit-save"
          :loading="submitting"
          :disabled="loading || submitting"
          @click="submit"
        >
          保存
        </el-button>
        <el-button :disabled="loading || submitting" @click="reset">重置</el-button>
      </div>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminClassOptions,
  getAdminSubjectPage,
  getAdminUser,
  saveAdminUser,
  type AdminClassListItem,
  type AdminSubjectListItem,
  type AdminUserEditModel
} from '@xzs/api-client'

const props = defineProps<{
  role: 1 | 2 | 3
}>()

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const submitting = ref(false)
const classOptions = ref<AdminClassListItem[]>([])
const subjectOptions = ref<AdminSubjectListItem[]>([])
const roleTitle = computed(() => {
  if (props.role === 1) return '学生'
  if (props.role === 2) return '老师'
  return '管理员'
})
const listPath = computed(() => {
  if (props.role === 1) return '/user/student/list'
  if (props.role === 2) return '/user/teacher/list'
  return '/user/admin/list'
})
const isCreateMode = computed(() => !Number(route.query.id || 0))
const passwordPlaceholder = computed(() => (isCreateMode.value ? '请输入登录密码' : '留空则不修改密码'))
const form = reactive<AdminUserEditModel>(createEmptyForm())
const rules: FormRules = {
  userName: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [
    {
      validator: (_rule: unknown, value: unknown, callback: (error?: Error) => void) => {
        if (isCreateMode.value && !String(value ?? '').trim()) {
          callback(new Error('请输入密码'))
          return
        }
        callback()
      },
      trigger: 'blur'
    }
  ],
  realName: [{ required: true, message: '请输入真实姓名', trigger: 'blur' }],
  classId: [{ required: props.role === 1, message: '请选择班级', trigger: 'change' }]
}

onMounted(async () => {
  if (props.role === 1) {
    const [classResult, subjectResult] = await Promise.all([
      getAdminClassOptions(),
      getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
    ])
    classOptions.value = classResult.response ?? []
    subjectOptions.value = subjectResult.response?.list ?? []
  }

  const id = Number(route.query.id || 0)
  if (!id) {
    return
  }

  loading.value = true
  try {
    const result = await getAdminUser(id)
    Object.assign(form, result.response)
  } finally {
    loading.value = false
  }
})

async function submit() {
  if (submitting.value) return

  try {
    const valid = await formRef.value?.validate()
    if (!valid) {
      focusFirstError()
      return
    }
  } catch {
    focusFirstError()
    return
  }

  submitting.value = true
  try {
    const payload: AdminUserEditModel = { ...form, role: props.role }
    payload.userName = String(payload.userName ?? '').trim()
    if (typeof payload.password === 'string') {
      payload.password = payload.password.trim()
    }
    if (payload.id && !payload.password) {
      delete payload.password
    }
    if (props.role === 1 && (payload.userLevel == null || payload.userLevel === 0)) {
      payload.userLevel = 1
    }
    if (props.role !== 1) {
      delete payload.targetSubjectId
    }
    const result = await saveAdminUser(payload)
    ElMessage.success(result.message || '保存成功')
    router.push(listPath.value)
  } finally {
    submitting.value = false
  }
}

async function reset() {
  try {
    await ElMessageBox.confirm('重置后当前填写的内容将被清空，是否继续？', '重置表单', { type: 'warning' })
  } catch {
    return
  }
  const id = form.id
  Object.assign(form, createEmptyForm(), { id })
  if (props.role !== 1) {
    delete form.targetSubjectId
  }
  formRef.value?.clearValidate()
}

function focusFirstError() {
  nextTick(() => {
    const firstError = document.querySelector<HTMLElement>('.user-edit-form .el-form-item.is-error')
    firstError?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    const input = firstError?.querySelector<HTMLElement>('input, textarea, [tabindex]:not([tabindex="-1"])')
    window.setTimeout(() => input?.focus({ preventScroll: true }), 250)
  })
}

function createEmptyForm(): AdminUserEditModel {
  return {
    id: null,
    userName: '',
    password: '',
    realName: '',
    nickName: '',
    role: props.role,
    status: 1,
    age: '',
    sex: undefined,
    birthDay: null,
    phone: '',
    userLevel: 1,
    classId: null,
    targetSubjectId: props.role === 1 ? null : undefined
  }
}
</script>

<style scoped>
.user-edit-form {
  max-width: 720px;
}

.user-edit__section {
  margin-bottom: 22px;
  padding-bottom: 6px;
  border-bottom: 1px solid var(--xzs-border);
}

.user-edit__section h2 {
  margin: 0 0 18px;
  color: var(--xzs-text);
  font-size: 16px;
}
</style>
