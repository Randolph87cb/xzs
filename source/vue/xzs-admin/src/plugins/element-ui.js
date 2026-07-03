import Vue from 'vue'
import Breadcrumb from 'element-ui/lib/breadcrumb'
import BreadcrumbItem from 'element-ui/lib/breadcrumb-item'
import Button from 'element-ui/lib/button'
import Card from 'element-ui/lib/card'
import Checkbox from 'element-ui/lib/checkbox'
import CheckboxGroup from 'element-ui/lib/checkbox-group'
import Col from 'element-ui/lib/col'
import ColorPicker from 'element-ui/lib/color-picker'
import DatePicker from 'element-ui/lib/date-picker'
import Dialog from 'element-ui/lib/dialog'
import Dropdown from 'element-ui/lib/dropdown'
import DropdownItem from 'element-ui/lib/dropdown-item'
import DropdownMenu from 'element-ui/lib/dropdown-menu'
import Form from 'element-ui/lib/form'
import FormItem from 'element-ui/lib/form-item'
import Input from 'element-ui/lib/input'
import InputNumber from 'element-ui/lib/input-number'
import Loading from 'element-ui/lib/loading'
import Menu from 'element-ui/lib/menu'
import MenuItem from 'element-ui/lib/menu-item'
import Message from 'element-ui/lib/message'
import MessageBox from 'element-ui/lib/message-box'
import Option from 'element-ui/lib/option'
import Pagination from 'element-ui/lib/pagination'
import Popover from 'element-ui/lib/popover'
import Radio from 'element-ui/lib/radio'
import RadioGroup from 'element-ui/lib/radio-group'
import Rate from 'element-ui/lib/rate'
import Row from 'element-ui/lib/row'
import Scrollbar from 'element-ui/lib/scrollbar'
import Select from 'element-ui/lib/select'
import Submenu from 'element-ui/lib/submenu'
import TabPane from 'element-ui/lib/tab-pane'
import Table from 'element-ui/lib/table'
import TableColumn from 'element-ui/lib/table-column'
import Tabs from 'element-ui/lib/tabs'
import Tag from 'element-ui/lib/tag'
import Timeline from 'element-ui/lib/timeline'
import TimelineItem from 'element-ui/lib/timeline-item'
import Tooltip from 'element-ui/lib/tooltip'
import '@/styles/element-variables.scss'

const components = [
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Card,
  Checkbox,
  CheckboxGroup,
  Col,
  ColorPicker,
  DatePicker,
  Dialog,
  Dropdown,
  DropdownItem,
  DropdownMenu,
  Form,
  FormItem,
  Input,
  InputNumber,
  Menu,
  MenuItem,
  Option,
  Pagination,
  Popover,
  Radio,
  RadioGroup,
  Rate,
  Row,
  Scrollbar,
  Select,
  Submenu,
  TabPane,
  Table,
  TableColumn,
  Tabs,
  Tag,
  Timeline,
  TimelineItem,
  Tooltip
]

Vue.prototype.$ELEMENT = {
  size: 'medium'
}

components.forEach(component => {
  Vue.use(component)
})

Vue.use(Loading.directive)
Vue.prototype.$loading = Loading.service
Vue.prototype.$message = Message
Vue.prototype.$msgbox = MessageBox
Vue.prototype.$alert = MessageBox.alert
Vue.prototype.$confirm = MessageBox.confirm
Vue.prototype.$prompt = MessageBox.prompt
