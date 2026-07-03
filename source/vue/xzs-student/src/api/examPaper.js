import { post } from '@/utils/request'

export default {
  select: id => post('/api/student/exam/paper/select/' + id),
  pageList: query => post('/api/student/exam/paper/pageList', query),
  smartTrainingCreate: query => post('/api/student/exam/paper/smartTraining/create', query)
}
