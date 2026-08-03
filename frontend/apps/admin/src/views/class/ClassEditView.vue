<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>班级编辑</h1>
        <p>维护班级名称、年级和负责老师。</p>
      </div>
    </header>

    <el-form ref="formRef" class="class-edit-form" :model="form" :rules="rules" label-width="92px">
      <el-form-item label="班级名称" prop="name">
        <el-input v-model="form.name" />
      </el-form-item>
      <el-form-item label="年级">
        <el-input-number v-model="form.gradeLevel" :min="1" :max="20" />
      </el-form-item>
      <el-form-item v-if="userStore.userInfo?.role !== 2" label="负责老师" prop="teacherId">
        <el-select v-model="form.teacherId" filterable placeholder="选择老师或管理员">
          <el-option
            v-for="teacher in teachers"
            :key="teacher.id"
            :label="teacherOptionLabel(teacher)"
            :value="teacher.id"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="状态">
        <el-select v-model="form.status">
          <el-option label="启用" :value="1" />
          <el-option label="禁用" :value="2" />
        </el-select>
      </el-form-item>
      <div class="admin-sticky-actions">
        <el-button type="primary" :loading="submitting" :disabled="loading || submitting" @click="submit">
          保存
        </el-button>
        <el-button :disabled="submitting" @click="router.push('/class/list')">返回</el-button>
      </div>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminClass,
  getAdminUserPage,
  saveAdminClass,
  type AdminClassEditModel,
  type AdminUserListItem
} from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const formRef = ref<FormInstance>()
const loading = ref(false)
const submitting = ref(false)
const teachers = ref<AdminUserListItem[]>([])
const form = reactive<AdminClassEditModel>({ id: null, name: '', gradeLevel: 1, teacherId: null, status: 1 })
const rules: FormRules = {
  name: [{ required: true, message: '请输入班级名称', trigger: 'blur' }],
  teacherId: [{ required: true, message: '请选择负责老师', trigger: 'change' }]
}

onMounted(async () => {
  if (userStore.userInfo?.role !== 2) {
    const [teacherResult, adminResult] = await Promise.all([
      getAdminUserPage({ role: 2, pageIndex: 1, pageSize: 100 }),
      getAdminUserPage({ role: 3, pageIndex: 1, pageSize: 100 })
    ])
    teachers.value = mergeTeacherCandidates([
      ...(teacherResult.response?.list ?? []),
      ...(adminResult.response?.list ?? [])
    ])
  }

  const id = Number(route.query.id || 0)
  if (!id) return
  loading.value = true
  try {
    const result = await getAdminClass(id)
    Object.assign(form, result.response)
  } finally {
    loading.value = false
  }
})

function mergeTeacherCandidates(candidates: AdminUserListItem[]) {
  const userMap = new Map<number, AdminUserListItem>()
  candidates.forEach((candidate) => userMap.set(candidate.id, candidate))
  return Array.from(userMap.values())
}

function teacherOptionLabel(teacher: AdminUserListItem) {
  const name = teacher.realName || teacher.userName
  return teacher.role === 3 ? `${name}（管理员）` : name
}

async function submit() {
  if (submitting.value) return
  try {
    const valid = await formRef.value?.validate()
    if (!valid) return
  } catch {
    return
  }
  submitting.value = true
  try {
    const result = await saveAdminClass(form)
    ElMessage.success(result.message || '保存成功')
    router.push('/class/list')
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.class-edit-form {
  max-width: 720px;
}
</style>
