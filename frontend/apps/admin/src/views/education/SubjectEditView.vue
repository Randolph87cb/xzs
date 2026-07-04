<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>学科编辑</h1>
        <p>维护考试学科基础数据。</p>
      </div>
    </header>

    <el-form :model="form" label-width="92px" style="max-width: 520px">
      <el-form-item label="学科" required>
        <el-input v-model="form.name" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="subject-edit-save" @click="submit">提交</el-button>
        <el-button @click="reset">重置</el-button>
      </el-form-item>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import { getAdminSubject, saveAdminSubject, type AdminSubjectEditModel } from '@xzs/api-client'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const form = reactive<AdminSubjectEditModel>({
  id: null,
  name: '',
  level: 1,
  levelName: ''
})

onMounted(async () => {
  const id = Number(route.query.id || 0)
  if (!id) {
    return
  }

  loading.value = true
  try {
    const result = await getAdminSubject(id)
    Object.assign(form, result.response)
  } finally {
    loading.value = false
  }
})

async function submit() {
  loading.value = true
  try {
    form.levelName = form.name
    const result = await saveAdminSubject(form)
    ElMessage.success(result.message || '保存成功')
    router.push('/education/subject/list')
  } finally {
    loading.value = false
  }
}

function reset() {
  const id = form.id
  Object.assign(form, {
    id,
    name: '',
    level: 1,
    levelName: ''
  })
}
</script>
