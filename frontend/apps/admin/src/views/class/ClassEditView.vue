<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>班级编辑</h1>
        <p>维护班级名称、年级和负责老师。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="92px" style="max-width: 720px">
      <el-form-item label="班级名称" prop="name">
        <el-input v-model="form.name" />
      </el-form-item>
      <el-form-item label="年级">
        <el-input-number v-model="form.gradeLevel" :min="1" :max="20" />
      </el-form-item>
      <el-form-item v-if="userStore.userInfo?.role !== 2" label="负责老师" prop="teacherId">
        <el-select v-model="form.teacherId" filterable placeholder="选择老师">
          <el-option v-for="teacher in teachers" :key="teacher.id" :label="teacher.realName || teacher.userName" :value="teacher.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="状态">
        <el-select v-model="form.status">
          <el-option label="启用" :value="1" />
          <el-option label="禁用" :value="2" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" @click="submit">提交</el-button>
        <el-button @click="router.push('/class/list')">返回</el-button>
      </el-form-item>
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
const teachers = ref<AdminUserListItem[]>([])
const form = reactive<AdminClassEditModel>({ id: null, name: '', gradeLevel: 1, teacherId: null, status: 1 })
const rules: FormRules = {
  name: [{ required: true, message: '请输入班级名称', trigger: 'blur' }],
  teacherId: [{ required: true, message: '请选择负责老师', trigger: 'change' }]
}

onMounted(async () => {
  if (userStore.userInfo?.role !== 2) {
    const teacherResult = await getAdminUserPage({ role: 2, pageIndex: 1, pageSize: 100 })
    teachers.value = teacherResult.response?.list ?? []
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

async function submit() {
  const valid = await formRef.value?.validate()
  if (!valid) return
  loading.value = true
  try {
    const result = await saveAdminClass(form)
    ElMessage.success(result.message || '保存成功')
    router.push('/class/list')
  } finally {
    loading.value = false
  }
}
</script>
