<template>
  <section class="training">
    <h1>智能训练</h1>
    <el-form v-loading="loadingSubjects" :model="form" label-position="top" class="training__form">
      <el-form-item label="训练科目">
        <el-select v-model="form.subjectId" placeholder="请选择科目">
          <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-button type="primary" :loading="creating" :disabled="!form.subjectId" @click="startTraining">开始训练</el-button>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { createSmartTrainingPaper, getSubjectList, type SubjectItem } from '@xzs/api-client'

const router = useRouter()
const subjects = ref<SubjectItem[]>([])
const loadingSubjects = ref(false)
const creating = ref(false)
const form = reactive({
  subjectId: undefined as number | undefined
})

onMounted(loadSubjects)

async function loadSubjects() {
  loadingSubjects.value = true
  try {
    const result = await getSubjectList()
    subjects.value = result.response ?? []
    form.subjectId = subjects.value[0]?.id
  } finally {
    loadingSubjects.value = false
  }
}

async function startTraining() {
  if (!form.subjectId) {
    ElMessage.warning('请选择科目')
    return
  }

  creating.value = true
  try {
    const result = await createSmartTrainingPaper({ subjectId: form.subjectId })
    if (result.code !== 1 || !result.response) {
      ElMessage.error(result.message)
      return
    }

    const paperId = resolvePaperId(result.response)
    if (!paperId) {
      ElMessage.error('训练卷生成失败')
      return
    }

    router.push({ path: '/do', query: { id: paperId } })
  } finally {
    creating.value = false
  }
}

function resolvePaperId(response: number | string | { id?: number; paperId?: number; examPaperId?: number }) {
  if (typeof response === 'number' || typeof response === 'string') {
    return response
  }

  return response.id ?? response.paperId ?? response.examPaperId
}
</script>

<style scoped lang="scss">
.training {
  display: grid;
  gap: 18px;
  max-width: 520px;
  padding: 24px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.training h1 {
  margin: 0;
  color: #111827;
  font-size: 22px;
}

.training__form {
  display: grid;
  gap: 8px;
}
</style>
