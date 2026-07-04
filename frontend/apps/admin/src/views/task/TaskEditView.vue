<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>任务创建</h1>
        <p>选择试卷并创建任务。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="92px">
      <el-form-item label="标题" prop="title">
        <el-input v-model="form.title" />
      </el-form-item>
      <el-form-item label="试卷">
        <el-table :data="form.paperItems" border>
          <el-table-column prop="id" label="Id" width="90" />
          <el-table-column label="学科" width="140">
            <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
          </el-table-column>
          <el-table-column prop="name" label="名称" min-width="220" show-overflow-tooltip />
          <el-table-column prop="createTime" label="创建时间" width="170" />
          <el-table-column label="操作" width="90">
            <template #default="{ $index }">
              <el-button size="small" type="danger" @click="form.paperItems.splice($index, 1)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="task-edit-save" @click="submit">提交</el-button>
        <el-button @click="openPaperDialog">添加试卷</el-button>
      </el-form-item>
    </el-form>

    <el-dialog v-model="paperDialogVisible" title="选择试卷" width="820px">
      <section class="admin-page__filters">
        <el-select v-model="paperQuery.subjectId" clearable placeholder="学科">
          <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
        <el-button @click="loadPapers">查询</el-button>
      </section>
      <el-table :data="paperRows" border @selection-change="selectedPapers = $event">
        <el-table-column type="selection" width="40" />
        <el-table-column prop="id" label="Id" width="90" />
        <el-table-column label="学科" width="140">
          <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
        </el-table-column>
        <el-table-column prop="name" label="名称" min-width="260" show-overflow-tooltip />
      </el-table>
      <template #footer>
        <el-button @click="paperDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="confirmPapers">确定</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminSubjectPage,
  getAdminTask,
  getAdminTaskExamPaperPage,
  saveAdminTask,
  type AdminExamPaperListItem,
  type AdminSubjectListItem,
  type AdminTaskEditModel
} from '@xzs/api-client'

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const paperDialogVisible = ref(false)
const paperRows = ref<AdminExamPaperListItem[]>([])
const selectedPapers = ref<AdminExamPaperListItem[]>([])
const form = reactive<AdminTaskEditModel>({ id: null, gradeLevel: 1, title: '', paperItems: [] })
const rules: FormRules = {
  title: [{ required: true, message: '请输入任务标题', trigger: 'blur' }]
}
const paperQuery = reactive({
  subjectId: null as number | null,
  paperType: 6,
  pageIndex: 1,
  pageSize: 8
})

onMounted(async () => {
  const subjectResult = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = subjectResult.response?.list ?? []

  const id = Number(route.query.id || 0)
  if (!id) return
  loading.value = true
  try {
    const result = await getAdminTask(id)
    Object.assign(form, result.response)
  } finally {
    loading.value = false
  }
})

async function openPaperDialog() {
  paperDialogVisible.value = true
  await loadPapers()
}

async function loadPapers() {
  const result = await getAdminTaskExamPaperPage(paperQuery)
  paperRows.value = result.response?.list ?? []
}

function confirmPapers() {
  form.paperItems.push(...selectedPapers.value)
  paperDialogVisible.value = false
}

async function submit() {
  const valid = await formRef.value?.validate()
  if (!valid) return
  if (form.paperItems.length === 0) {
    ElMessage.error('请添加试卷')
    return
  }
  loading.value = true
  try {
    const result = await saveAdminTask(form)
    ElMessage.success(result.message || '保存成功')
    router.push('/task/list')
  } finally {
    loading.value = false
  }
}

function subjectName(subjectId?: number) {
  return subjects.value.find((item) => item.id === subjectId)?.name ?? ''
}
</script>
