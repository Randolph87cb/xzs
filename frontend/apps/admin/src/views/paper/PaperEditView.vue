<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>试卷编辑</h1>
        <p>配置试卷基础信息和题目分组。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="100px">
      <el-form-item label="学科" prop="subjectId">
        <el-select v-model="form.subjectId" placeholder="学科" style="width: 240px">
          <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="试卷类型" prop="paperType">
        <el-select v-model="form.paperType" style="width: 240px">
          <el-option label="固定试卷" :value="1" />
          <el-option label="时段试卷" :value="4" />
          <el-option label="任务试卷" :value="6" />
        </el-select>
      </el-form-item>
      <el-form-item label="试卷名称" prop="name">
        <el-input v-model="form.name" />
      </el-form-item>
      <el-form-item label="建议时长" prop="suggestTime">
        <el-input-number v-model="form.suggestTime" :min="1" />
      </el-form-item>
      <el-form-item v-for="(title, index) in form.titleItems" :key="index" :label="`标题${index + 1}`">
        <div class="paper-title-editor">
          <el-input v-model="title.name" placeholder="标题名称" />
          <div class="admin-page__actions">
            <el-button @click="openQuestionDialog(title)">添加题目</el-button>
            <el-button type="danger" @click="form.titleItems.splice(index, 1)">删除标题</el-button>
          </div>
          <el-table :data="title.questionItems" border>
            <el-table-column prop="id" label="Id" width="90" />
            <el-table-column prop="questionType" label="题型" width="100">
              <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
            </el-table-column>
            <el-table-column prop="title" label="题干" min-width="220" show-overflow-tooltip />
            <el-table-column label="操作" width="90">
              <template #default="{ $index }">
                <el-button size="small" type="danger" @click="title.questionItems.splice($index, 1)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
        </div>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="paper-edit-save" @click="submit">提交</el-button>
        <el-button @click="addTitle">添加标题</el-button>
      </el-form-item>
    </el-form>

    <el-dialog v-model="questionDialogVisible" title="选择题目" width="860px">
      <section class="admin-page__filters">
        <el-input v-model.number="questionQuery.id" clearable placeholder="题目 ID" />
        <el-select v-model="questionQuery.questionType" clearable placeholder="题型">
          <el-option v-for="item in questionTypes" :key="item.value" :label="item.label" :value="item.value" />
        </el-select>
        <el-button @click="loadQuestions">查询</el-button>
      </section>
      <el-table :data="questionRows" border @selection-change="selectedQuestions = $event">
        <el-table-column type="selection" width="40" />
        <el-table-column prop="id" label="Id" width="90" />
        <el-table-column prop="questionType" label="题型" width="100">
          <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
        </el-table-column>
        <el-table-column prop="shortTitle" label="题干" min-width="260" show-overflow-tooltip />
      </el-table>
      <template #footer>
        <el-button @click="questionDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="confirmQuestions">确定</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminExamPaper,
  getAdminQuestion,
  getAdminQuestionPage,
  getAdminSubjectPage,
  saveAdminExamPaper,
  type AdminExamPaperEditModel,
  type AdminExamPaperTitleItem,
  type AdminQuestionListItem,
  type AdminSubjectListItem
} from '@xzs/api-client'

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const questionDialogVisible = ref(false)
const currentTitle = ref<AdminExamPaperTitleItem | null>(null)
const questionRows = ref<AdminQuestionListItem[]>([])
const selectedQuestions = ref<AdminQuestionListItem[]>([])
const form = reactive<AdminExamPaperEditModel>({
  id: null,
  level: 1,
  subjectId: null,
  paperType: 1,
  limitDateTime: [],
  name: '',
  suggestTime: 60,
  titleItems: [{ name: '一、选择题', questionItems: [] }]
})
const rules: FormRules = {
  subjectId: [{ required: true, message: '请选择学科', trigger: 'change' }],
  paperType: [{ required: true, message: '请选择试卷类型', trigger: 'change' }],
  name: [{ required: true, message: '请输入试卷名称', trigger: 'blur' }],
  suggestTime: [{ required: true, message: '请输入建议时长', trigger: 'blur' }]
}
const questionQuery = reactive({
  id: null as number | null,
  level: null,
  subjectId: null as number | null,
  questionType: null as number | null,
  knowledgePoint: null,
  pageIndex: 1,
  pageSize: 8
})
const questionTypes = [
  { value: 1, label: '单选题' },
  { value: 2, label: '多选题' },
  { value: 3, label: '判断题' },
  { value: 4, label: '填空题' },
  { value: 5, label: '简答题' }
]

onMounted(async () => {
  const subjectResult = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = subjectResult.response?.list ?? []

  const id = Number(route.query.id || 0)
  if (!id) return
  loading.value = true
  try {
    const result = await getAdminExamPaper(id)
    Object.assign(form, result.response)
  } finally {
    loading.value = false
  }
})

function addTitle() {
  form.titleItems.push({ name: '', questionItems: [] })
}

async function openQuestionDialog(title: AdminExamPaperTitleItem) {
  currentTitle.value = title
  questionQuery.subjectId = form.subjectId
  questionDialogVisible.value = true
  await loadQuestions()
}

async function loadQuestions() {
  questionQuery.subjectId = form.subjectId
  const result = await getAdminQuestionPage(questionQuery)
  questionRows.value = result.response?.list ?? []
}

async function confirmQuestions() {
  const target = currentTitle.value
  if (!target) return
  const details = await Promise.all(selectedQuestions.value.map((item) => getAdminQuestion(item.id)))
  for (const detail of details) {
    if (detail.response) {
      target.questionItems.push(detail.response)
    }
  }
  questionDialogVisible.value = false
}

async function submit() {
  const valid = await formRef.value?.validate()
  if (!valid) return
  loading.value = true
  try {
    const result = await saveAdminExamPaper(form)
    ElMessage.success(result.message || '保存成功')
    router.push('/exam/paper/list')
  } finally {
    loading.value = false
  }
}

function questionTypeText(type?: number) {
  return questionTypes.find((item) => item.value === type)?.label ?? '-'
}
</script>

<style scoped>
.paper-title-editor {
  display: grid;
  gap: 10px;
  width: 100%;
}
</style>
