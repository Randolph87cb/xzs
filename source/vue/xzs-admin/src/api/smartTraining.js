import { post } from '@/utils/request'

export default {
  configList: query => post('/api/admin/smartTraining/config/list', query),
  configSelect: subjectId => post('/api/admin/smartTraining/config/select/' + subjectId),
  configEdit: query => post('/api/admin/smartTraining/config/edit', query),
  knowledgePoints: subjectId => post('/api/admin/smartTraining/knowledgePoints/' + subjectId)
}
