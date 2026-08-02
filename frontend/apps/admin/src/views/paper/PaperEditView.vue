<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>试卷编辑</h1>
        <p>独立题逐题加入，题组作为不可拆分的整体加入、排序和删除。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="100px">
      <el-form-item label="学科" prop="subjectId">
        <el-select v-model="form.subjectId" placeholder="学科" style="width: 240px" @change="handleSubjectChange">
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
      <el-form-item v-for="(title, titleIndex) in form.titleItems" :key="titleIndex" :label="`标题${titleIndex + 1}`">
        <div class="paper-title-editor">
          <el-input v-model="title.name" placeholder="标题名称" />
          <div class="admin-page__actions">
            <el-button @click="openQuestionDialog(title)">添加独立题</el-button>
            <el-button type="primary" plain @click="openGroupDialog(title)">添加题组</el-button>
            <el-button type="danger" @click="removeTitle(titleIndex)">删除标题</el-button>
          </div>

          <el-empty v-if="!title.paperItems?.length" description="尚未添加独立题或题组" :image-size="64" />
          <article
            v-for="(paperItem, paperItemIndex) in title.paperItems ?? []"
            :key="`${paperItem.type}-${paperItem.id}-${paperItemIndex}`"
            class="paper-unit"
            :class="{ 'is-question-group': paperItem.type === 'QUESTION_GROUP' }"
          >
            <header class="paper-unit__header">
              <div class="paper-unit__identity">
                <el-tag :type="paperItem.type === 'QUESTION_GROUP' ? 'primary' : 'info'">
                  {{ paperItem.type === 'QUESTION_GROUP' ? '题组' : '独立题' }}
                </el-tag>
                <strong v-if="paperItem.type === 'QUESTION_GROUP'">
                  {{ groupTypeText(paperItem.questionGroupType) }} · {{ paperItem.questionGroupCode || `#${paperItem.id}` }}
                </strong>
                <strong v-else>题目 #{{ paperItem.id }}</strong>
                <span>{{ paperItem.questionItems.length }} 个答题项 / {{ paperItemScore(paperItem) }} 分</span>
              </div>
              <div class="admin-page__actions">
                <el-button size="small" :disabled="paperItemIndex === 0" @click="movePaperItem(title, paperItemIndex, -1)">上移</el-button>
                <el-button
                  size="small"
                  :disabled="paperItemIndex === (title.paperItems?.length ?? 0) - 1"
                  @click="movePaperItem(title, paperItemIndex, 1)"
                >下移</el-button>
                <el-button size="small" type="danger" @click="removePaperItem(title, paperItemIndex)">整项删除</el-button>
              </div>
            </header>

            <section v-if="paperItem.type === 'QUESTION_GROUP'" class="paper-unit__shared-title">
              <QuestionMarkdown :content="paperItem.title || '题组共享题面缺失'" />
            </section>

            <el-table :data="paperItem.questionItems" border size="small">
              <el-table-column prop="id" label="题目 Id" width="90" />
              <el-table-column v-if="paperItem.type === 'QUESTION_GROUP'" prop="groupItemOrder" label="组内顺序" width="90" />
              <el-table-column prop="questionType" label="题型" width="100">
                <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
              </el-table-column>
              <el-table-column prop="title" label="题干" min-width="240" show-overflow-tooltip />
              <el-table-column prop="score" label="分数" width="75" />
            </el-table>
            <p v-if="paperItem.type === 'QUESTION_GROUP'" class="paper-unit__hint">组内子题为只读快照，试卷内不能单独删除。</p>
          </article>
        </div>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="paper-edit-save" @click="submit">提交</el-button>
        <el-button @click="addTitle">添加标题</el-button>
      </el-form-item>
    </el-form>

    <el-dialog v-model="questionDialogVisible" title="选择独立题" width="900px">
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
        <el-button type="primary" @click="confirmQuestions">加入独立题</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="groupDialogVisible" title="选择题组" width="960px">
      <section class="admin-page__filters">
        <el-input v-model.number="groupQuery.id" clearable placeholder="题组 ID" />
        <el-select v-model="groupQuery.groupType" clearable placeholder="题组类型">
          <el-option label="程序阅读" :value="1" />
          <el-option label="程序填空" :value="2" />
        </el-select>
        <el-input v-model="groupQuery.knowledgePoint" clearable placeholder="知识点" />
        <el-button @click="loadGroups">查询</el-button>
      </section>
      <el-table :data="groupRows" border @selection-change="selectedGroups = $event">
        <el-table-column type="selection" width="40" />
        <el-table-column prop="id" label="Id" width="75" />
        <el-table-column prop="groupType" label="类型" width="105">
          <template #default="{ row }">{{ groupTypeText(row.groupType) }}</template>
        </el-table-column>
        <el-table-column prop="groupCode" label="题组编号" width="180" show-overflow-tooltip />
        <el-table-column prop="title" label="共享题面" min-width="250" show-overflow-tooltip />
        <el-table-column prop="questionCount" label="子题数" width="80" />
        <el-table-column prop="totalScore" label="总分" width="70" />
        <el-table-column prop="importSource" label="来源" width="150" show-overflow-tooltip />
      </el-table>
      <template #footer>
        <el-button @click="groupDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="confirmGroups">整组加入</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { useRoute, useRouter } from 'vue-router'
import {
  getAdminExamPaper,
  getAdminQuestion,
  getAdminQuestionGroupPage,
  getAdminQuestionPage,
  getAdminSubjectPage,
  saveAdminExamPaper,
  type AdminExamPaperEditModel,
  type AdminExamPaperItem,
  type AdminExamPaperTitleItem,
  type AdminQuestionGroupEditModel,
  type AdminQuestionListItem,
  type AdminSubjectListItem
} from '@xzs/api-client'

const route = useRoute()
const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const questionDialogVisible = ref(false)
const groupDialogVisible = ref(false)
const currentTitle = ref<AdminExamPaperTitleItem | null>(null)
const questionRows = ref<AdminQuestionListItem[]>([])
const selectedQuestions = ref<AdminQuestionListItem[]>([])
const groupRows = ref<AdminQuestionGroupEditModel[]>([])
const selectedGroups = ref<AdminQuestionGroupEditModel[]>([])
const form = reactive<AdminExamPaperEditModel>({
  id: null,
  level: 1,
  subjectId: null,
  paperType: 1,
  limitDateTime: [],
  name: '',
  suggestTime: 60,
  titleItems: [{ name: '一、选择题', questionItems: [], paperItems: [] }]
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
  questionGroupMode: 'INDEPENDENT' as const,
  pageIndex: 1,
  pageSize: 20
})
const groupQuery = reactive({
  id: null as number | null,
  subjectId: null as number | null,
  groupType: null as 1 | 2 | null,
  knowledgePoint: null as string | null,
  status: 1,
  pageIndex: 1,
  pageSize: 20
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
    if (result.response) {
      Object.assign(form, normalizePaper(result.response))
    }
  } finally {
    loading.value = false
  }
})

function normalizePaper(paper: AdminExamPaperEditModel): AdminExamPaperEditModel {
  return {
    ...paper,
    titleItems: (paper.titleItems ?? []).map((title) => {
      const paperItems = title.paperItems?.length
        ? title.paperItems.map((item) => ({ ...item, questionItems: item.questionItems ?? [] }))
        : (title.questionItems ?? []).map((question): AdminExamPaperItem => ({
            type: 'QUESTION',
            id: question.id as number,
            itemOrder: question.itemOrder,
            questionItems: [question]
          }))
      return { ...title, questionItems: title.questionItems ?? [], paperItems }
    })
  }
}

function addTitle() {
  form.titleItems.push({ name: '', questionItems: [], paperItems: [] })
}

function removeTitle(index: number) {
  ElMessageBox.confirm('确认删除该标题及其全部试卷条目？', '删除标题', { type: 'warning' })
    .then(() => form.titleItems.splice(index, 1))
    .catch(() => undefined)
}

async function openQuestionDialog(title: AdminExamPaperTitleItem) {
  if (!ensureSubjectSelected()) return
  currentTitle.value = title
  selectedQuestions.value = []
  questionQuery.subjectId = form.subjectId
  questionDialogVisible.value = true
  await loadQuestions()
}

async function openGroupDialog(title: AdminExamPaperTitleItem) {
  if (!ensureSubjectSelected()) return
  currentTitle.value = title
  selectedGroups.value = []
  groupQuery.subjectId = form.subjectId
  groupDialogVisible.value = true
  await loadGroups()
}

async function loadQuestions() {
  questionQuery.subjectId = form.subjectId
  const result = await getAdminQuestionPage(questionQuery)
  questionRows.value = result.response?.list ?? []
}

async function loadGroups() {
  groupQuery.subjectId = form.subjectId
  const result = await getAdminQuestionGroupPage(groupQuery)
  groupRows.value = result.response?.list ?? []
}

async function confirmQuestions() {
  const target = currentTitle.value
  if (!target) return
  const details = await Promise.all(selectedQuestions.value.map((item) => getAdminQuestion(item.id)))
  let added = 0
  for (const detail of details) {
    const question = detail.response
    if (!question?.id || containsPaperItem('QUESTION', question.id)) continue
    target.paperItems ??= []
    target.paperItems.push({ type: 'QUESTION', id: question.id, questionItems: [question] })
    added += 1
  }
  syncTitleQuestionItems(target)
  questionDialogVisible.value = false
  ElMessage.success(`已加入 ${added} 道独立题`)
}

function confirmGroups() {
  const target = currentTitle.value
  if (!target) return
  let added = 0
  for (const group of selectedGroups.value) {
    if (!group.id || containsPaperItem('QUESTION_GROUP', group.id)) continue
    target.paperItems ??= []
    target.paperItems.push({
      type: 'QUESTION_GROUP',
      id: group.id,
      questionGroupType: group.groupType,
      questionGroupCode: group.groupCode,
      title: group.title,
      questionItems: group.questionItems
    })
    added += 1
  }
  syncTitleQuestionItems(target)
  groupDialogVisible.value = false
  ElMessage.success(`已整组加入 ${added} 个题组`)
}

function movePaperItem(title: AdminExamPaperTitleItem, index: number, offset: number) {
  const target = index + offset
  const paperItems = title.paperItems ?? []
  if (target < 0 || target >= paperItems.length) return
  const [item] = paperItems.splice(index, 1)
  paperItems.splice(target, 0, item)
  syncTitleQuestionItems(title)
}

function removePaperItem(title: AdminExamPaperTitleItem, index: number) {
  title.paperItems?.splice(index, 1)
  syncTitleQuestionItems(title)
}

function syncTitleQuestionItems(title: AdminExamPaperTitleItem) {
  title.questionItems = (title.paperItems ?? []).flatMap((item) => item.questionItems)
}

function containsPaperItem(type: AdminExamPaperItem['type'], id: number) {
  return form.titleItems.some((title) => title.paperItems?.some((item) => item.type === type && item.id === id))
}

function handleSubjectChange() {
  const hasPaperItems = form.titleItems.some((title) => title.paperItems?.length)
  if (hasPaperItems) {
    form.titleItems.forEach((title) => {
      title.paperItems = []
      title.questionItems = []
    })
    ElMessage.warning('学科已切换，原有题目和题组已清空，请重新选择')
  }
}

async function submit() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return
  if (!form.titleItems.length || form.titleItems.some((title) => !title.name.trim() || !title.paperItems?.length)) {
    ElMessage.error('每个标题都需要名称，并至少包含一道独立题或一个题组')
    return
  }

  loading.value = true
  try {
    const payload: AdminExamPaperEditModel = {
      ...form,
      titleItems: form.titleItems.map((title) => ({
        ...title,
        paperItems: title.paperItems?.map((item) => ({ ...item, questionItems: [...item.questionItems] })) ?? [],
        questionItems: (title.paperItems ?? []).flatMap((item) => item.questionItems)
      }))
    }
    const result = await saveAdminExamPaper(payload)
    if (result.code === 1) {
      ElMessage.success(result.message || '保存成功')
      router.push('/exam/paper/list')
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    loading.value = false
  }
}

function ensureSubjectSelected() {
  if (form.subjectId) return true
  ElMessage.warning('请先选择学科')
  return false
}

function paperItemScore(item: AdminExamPaperItem) {
  return item.questionItems.reduce((sum, question) => sum + (Number(question.score) || 0), 0)
}

function questionTypeText(type?: number) {
  return questionTypes.find((item) => item.value === type)?.label ?? '-'
}

function groupTypeText(type?: number | null) {
  return type === 2 ? '程序填空' : '程序阅读'
}
</script>

<style scoped lang="scss">
.paper-title-editor {
  display: grid;
  gap: 12px;
  width: 100%;
}

.paper-unit {
  display: grid;
  gap: 10px;
  padding: 14px;
  border: 1px solid var(--el-border-color);
  border-radius: 6px;
  background: var(--el-fill-color-blank);
}

.paper-unit.is-question-group {
  border-color: var(--el-color-primary-light-7);
  background: var(--el-color-primary-light-9);
}

.paper-unit__header,
.paper-unit__identity {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
}

.paper-unit__header {
  justify-content: space-between;
}

.paper-unit__identity span {
  color: var(--el-text-color-secondary);
  font-size: 13px;
}

.paper-unit__shared-title {
  max-height: 280px;
  padding: 12px 14px;
  overflow: auto;
  border: 1px solid var(--el-color-primary-light-7);
  border-radius: 6px;
  background: var(--el-bg-color);
}

.paper-unit__hint {
  margin: 0;
  color: var(--el-text-color-secondary);
  font-size: 13px;
}
</style>
