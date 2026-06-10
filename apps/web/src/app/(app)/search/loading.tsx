export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-24 rounded-xl glass-light" />
      <div className="h-12 rounded-2xl glass-light" />
      {[1,2,3].map((i) => (
        <div key={i} className="flex flex-col gap-2">
          <div className="h-4 w-20 rounded-full glass-light" />
          <div className="h-14 rounded-xl glass-light" />
          <div className="h-14 rounded-xl glass-light" />
        </div>
      ))}
    </div>
  )
}
