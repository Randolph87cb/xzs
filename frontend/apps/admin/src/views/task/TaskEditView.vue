<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>{{ pageTitle }}</h1>
        <p>选择发布班级和试卷，完成任务发布。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="92px">
      <el-form-item label="标题" prop="title">
        <el-input v-model="form.title" />
      </el-form-item>
      <el-form-item label="发布班级" prop="classId">
        <el-select v-model="form.classId" :clearable="!isTeacher" filterable placeholder="选择班级">
          <el-option v-for="item in classOptions" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="试卷">
        <el-table class="desktop-only" :data="form.paperItems" border>
          <el-table-column prop="id" label="Id" width="90" />
          <el-table-column label="学科" width="140">
            <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
          </el-table-column>
          <el-table-column prop="name" label="名称" min-width="220" show-overflow-tooltip />
          <el-table-column prop="createTime" label="创建时间" width="170" />
          <el-table-column label="操作" width="90">
            <template #default="{ $index }">
              <el-button size="small" type="danger" @click="removePaper($index)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
        <div class="mobile-only task-edit__selected-papers">
          <div class="admin-mobile-cards">
            <article v-for="(paper, index) in form.paperItems" :key="paper.id" class="admin-mobile-card">
            <div class="admin-mobile-card__header">
              <strong>{{ paper.name }}</strong>
              <el-tag size="small" type="info">{{ subjectName(paper.subjectId) || '未分类' }}</el-tag>
            </div>
            <div class="admin-mobile-field">
              <span class="admin-mobile-field__label">创建时间</span>
              <span class="admin-mobile-field__value">{{ paper.createTime || '—' }}</span>
            </div>
            <div class="admin-mobile-card__actions">
              <el-button type="danger" plain @click="removePaper(index)">移除试卷</el-button>
            </div>
            </article>
            <el-empty v-if="form.paperItems.length === 0" description="尚未添加试卷" />
          </div>
        </div>
      </el-form-item>
      <div v-show="!paperDialogVisible" class="admin-sticky-actions task-edit__actions">
        <el-button
          type="primary"
          data-testid="task-edit-save"
          :loading="submitting"
          :disabled="loading || submitting"
          @click="submit"
        >
          保存任务
        </el-button>
        <el-button :disabled="loading || submitting" @click="openPaperDialog">选择试卷</el-button>
        <el-button :disabled="submitting" @click="router.push('/task/list')">返回列表</el-button>
      </div>
    </el-form>

    <el-dialog
      v-model="paperDialogVisible"
      class="admin-dialog--mobile-full"
      data-testid="task-paper-dialog"
      title="选择试卷"
      width="820px"
      destroy-on-close
    >
      <div
        v-loading="paperLoading"
        class="task-edit__dialog-body"
        data-testid="task-paper-dialog-body"
        element-loading-text="正在加载试卷…"
      >
        <section class="admin-page__filters">
          <el-select
            v-model="paperQuery.subjectId"
            clearable
            :disabled="paperLoading"
            placeholder="学科"
            @change="searchPapers"
          >
            <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
          <el-button :loading="paperLoading" :disabled="paperLoading" @click="searchPapers">查询</el-button>
        </section>
        <el-table
          ref="paperTableRef"
          class="desktop-only"
          :data="paperRows"
          row-key="id"
          border
          @selection-change="handlePaperSelectionChange"
        >
          <el-table-column type="selection" width="40" :reserve-selection="true" />
          <el-table-column prop="id" label="Id" width="90" />
          <el-table-column label="学科" width="140">
            <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
          </el-table-column>
          <el-table-column prop="name" label="名称" min-width="260" show-overflow-tooltip />
        </el-table>
        <div class="mobile-only task-edit__paper-options">
          <div class="admin-mobile-cards">
            <article
              v-for="paper in paperRows"
              :key="paper.id"
              class="admin-mobile-card"
              :data-testid="`task-paper-option-${paper.id}`"
            >
              <el-checkbox
                :model-value="selectedPaperMap.has(paper.id)"
                @change="toggleMobilePaper(paper, $event)"
              >
                <strong>{{ paper.name }}</strong>
              </el-checkbox>
              <div class="admin-mobile-field">
                <span class="admin-mobile-field__label">学科</span>
                <span class="admin-mobile-field__value">{{ subjectName(paper.subjectId) || '未分类' }}</span>
              </div>
            </article>
            <el-empty v-if="!paperLoading && paperRows.length === 0" description="暂无可选试卷" />
          </div>
        </div>
        <footer class="admin-page__pagination task-edit__paper-pagination">
          <el-pagination
            v-model:current-page="paperQuery.pageIndex"
            background
            layout="total, prev, pager, next"
            :disabled="paperLoading"
            :page-size="paperQuery.pageSize"
            :total="paperTotal"
            @current-change="loadPapers"
          />
        </footer>
      </div>
      <template #footer>
        <div class="admin-sticky-actions task-edit__dialog-actions">
          <el-button data-testid="task-paper-dialog-cancel" @click="paperDialogVisible = false">取消</el-button>
          <el-button
            type="primary"
            data-testid="task-paper-dialog-confirm"
            :loading="paperLoading"
            :disabled="paperLoading"
            @click="confirmPapers"
          >
            确定（{{ selectedPaperMap.size }}）
          </el-button>
        </div>
      </template>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import {
  getAdminClassOptions,
  getAdminSubjectPage,
  getAdminTask,
  getAdminTaskExamPaperPage,
  saveAdminTask,
  type AdminClassListItem,
  type AdminExamPaperListItem,
  type AdminSubjectListItem,
  type AdminTaskEditModel
} from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const formRef = ref<FormInstance>()
const loading = ref(false)
const submitting = ref(false)
const paperLoading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const classOptions = ref<AdminClassListItem[]>([])
const paperDialogVisible = ref(false)
const paperRows = ref<AdminExamPaperListItem[]>([])
const paperTotal = ref(0)
const selectedPaperMap = ref(new Map<number, AdminExamPaperListItem>())
const paperTableRef = ref<{
  clearSelection: () => void
  toggleRowSelection: (row: AdminExamPaperListItem, selected?: boolean) => void
}>()
const syncingTableSelection = ref(false)
const baseline = ref('')
const formReady = ref(false)
const allowLeave = ref(false)
const form = reactive<AdminTaskEditModel>({ id: null, gradeLevel: 1, classId: null, title: '', paperItems: [] })
const isTeacher = computed(() => userStore.userInfo?.role === 2)
const pageTitle = computed(() => (Number(route.query.id || 0) ? '任务编辑' : '任务创建'))
const isDirty = computed(() => formReady.value && !allowLeave.value && taskSignature() !== baseline.value)
const rules: FormRules = {
  title: [{ required: true, message: '请输入任务标题', trigger: 'blur' }],
  classId: [
    {
      validator: (_rule, value, callback) => {
        if (isTeacher.value && !value) {
          callback(new Error('请选择发布班级'))
          return
        }
        callback()
      },
      trigger: 'change'
    }
  ]
}
const paperQuery = reactive({
  subjectId: null as number | null,
  paperType: 1 as number | null,
  level: null as number | null,
  pageIndex: 1,
  pageSize: 8
})

onMounted(async () => {
  window.addEventListener('beforeunload', handleBeforeUnload)
  loading.value = true
  try {
    const [subjectResult, classResult] = await Promise.all([
      getAdminSubjectPage({ pageIndex: 1, pageSize: 100 }),
      getAdminClassOptions()
    ])
    subjects.value = subjectResult.response?.list ?? []
    classOptions.value = classResult.response ?? []
    if (isTeacher.value && !form.classId && classOptions.value.length === 1) {
      form.classId = classOptions.value[0].id
    }

    const id = Number(route.query.id || 0)
    if (id) {
      const result = await getAdminTask(id)
      if (result.response) {
        Object.assign(form, result.response, { paperItems: result.response.paperItems ?? [] })
      }
      if (isTeacher.value && !form.classId && classOptions.value.length === 1) {
        form.classId = classOptions.value[0].id
      }
    }
  } finally {
    loading.value = false
    markBaseline()
  }
})

onBeforeUnmount(() => window.removeEventListener('beforeunload', handleBeforeUnload))

onBeforeRouteLeave(async () => {
  if (!isDirty.value) return true
  try {
    await ElMessageBox.confirm('当前任务有未保存的修改，确认离开？', '未保存修改', {
      type: 'warning',
      confirmButtonText: '离开',
      cancelButtonText: '继续编辑'
    })
    return true
  } catch {
    return false
  }
})

async function openPaperDialog() {
  selectedPaperMap.value = new Map(form.paperItems.map((paper) => [paper.id, paper]))
  paperQuery.pageIndex = 1
  paperDialogVisible.value = true
  await loadPapers()
}

async function loadPapers() {
  paperLoading.value = true
  try {
    const result = await getAdminTaskExamPaperPage(paperQuery)
    paperRows.value = result.response?.list ?? []
    paperTotal.value = result.response?.total ?? 0
    paperQuery.pageIndex = result.response?.pageNum ?? paperQuery.pageIndex
    await syncTableSelection()
  } finally {
    paperLoading.value = false
  }
}

function searchPapers() {
  paperQuery.pageIndex = 1
  loadPapers()
}

function handlePaperSelectionChange(rows: AdminExamPaperListItem[]) {
  if (syncingTableSelection.value) return
  paperRows.value.forEach((paper) => selectedPaperMap.value.delete(paper.id))
  rows.forEach((paper) => selectedPaperMap.value.set(paper.id, paper))
}

async function syncTableSelection() {
  await nextTick()
  if (!paperTableRef.value) return
  syncingTableSelection.value = true
  paperTableRef.value.clearSelection()
  paperRows.value.forEach((paper) => {
    if (selectedPaperMap.value.has(paper.id)) {
      paperTableRef.value?.toggleRowSelection(paper, true)
    }
  })
  await nextTick()
  syncingTableSelection.value = false
}

function toggleMobilePaper(paper: AdminExamPaperListItem, checked: unknown) {
  if (Boolean(checked)) {
    selectedPaperMap.value.set(paper.id, paper)
  } else {
    selectedPaperMap.value.delete(paper.id)
  }
}

function confirmPapers() {
  form.paperItems = Array.from(selectedPaperMap.value.values())
  paperDialogVisible.value = false
}

async function submit() {
  if (submitting.value) return
  try {
    const valid = await formRef.value?.validate()
    if (!valid) return
  } catch {
    return
  }
  if (form.paperItems.length === 0) {
    ElMessage.error('请添加试卷')
    return
  }
  if (isTeacher.value && !form.classId) {
    ElMessage.error('请选择发布班级')
    return
  }
  submitting.value = true
  try {
    const result = await saveAdminTask(form)
    ElMessage.success(result.message || '保存成功')
    allowLeave.value = true
    markBaseline()
    await router.push('/task/list')
  } finally {
    submitting.value = false
  }
}

function removePaper(index: number) {
  form.paperItems.splice(index, 1)
}

function markBaseline() {
  baseline.value = taskSignature()
  formReady.value = true
}

function taskSignature() {
  return JSON.stringify({
    title: form.title,
    classId: form.classId ?? null,
    paperIds: form.paperItems.map((paper) => paper.id)
  })
}

function handleBeforeUnload(event: BeforeUnloadEvent) {
  if (!isDirty.value) return
  event.preventDefault()
  event.returnValue = ''
}

function subjectName(subjectId?: number) {
  return subjects.value.find((item) => item.id === subjectId)?.name ?? ''
}
</script>

<style scoped>
.task-edit__selected-papers,
.task-edit__paper-options {
  width: 100%;
}

.task-edit__paper-pagination {
  margin-top: 16px;
}

.task-edit__dialog-body {
  position: relative;
  min-height: 240px;
}

.task-edit__dialog-actions {
  padding-top: 0;
}

.task-edit__paper-options :deep(.el-checkbox) {
  width: 100%;
  height: auto;
  min-height: 44px;
  margin-right: 0;
  white-space: normal;
}

.task-edit__paper-options :deep(.el-checkbox__label) {
  min-width: 0;
  overflow-wrap: anywhere;
}
</style>
